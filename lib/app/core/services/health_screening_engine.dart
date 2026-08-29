/// Central, deterministic screening and data-quality logic for check-up data.
///
/// This is decision support only. It does not diagnose, prescribe treatment, or
/// submit referrals. The result is intentionally structured so the check-up
/// workflow, referral review, and scoped analytics can all use the same source.
library;

import 'dart:convert';

enum HealthScreeningStatus {
  withinExpectedRange,
  needsAttention,
  referralReview,
  urgentAssessment,
  needsProfessionalReview,
}

extension HealthScreeningStatusLabel on HealthScreeningStatus {
  String get label {
    switch (this) {
      case HealthScreeningStatus.withinExpectedRange:
        return 'WITHIN EXPECTED RANGE';
      case HealthScreeningStatus.needsAttention:
        return 'NEEDS ATTENTION';
      case HealthScreeningStatus.referralReview:
        return 'REFERRAL REVIEW';
      case HealthScreeningStatus.urgentAssessment:
        return 'URGENT ASSESSMENT';
      case HealthScreeningStatus.needsProfessionalReview:
        return 'NEEDS PROFESSIONAL REVIEW';
    }
  }

  int get priority {
    switch (this) {
      case HealthScreeningStatus.withinExpectedRange:
        return 0;
      case HealthScreeningStatus.needsAttention:
        return 1;
      case HealthScreeningStatus.needsProfessionalReview:
        return 2;
      case HealthScreeningStatus.referralReview:
        return 3;
      case HealthScreeningStatus.urgentAssessment:
        return 4;
    }
  }

  static HealthScreeningStatus fromLabel(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.contains('urgent')) {
      return HealthScreeningStatus.urgentAssessment;
    }
    if (normalized.contains('referral')) {
      return HealthScreeningStatus.referralReview;
    }
    if (normalized.contains('professional')) {
      return HealthScreeningStatus.needsProfessionalReview;
    }
    if (normalized.contains('attention')) {
      return HealthScreeningStatus.needsAttention;
    }
    return HealthScreeningStatus.withinExpectedRange;
  }
}

enum HealthReferralRecommendation {
  noCurrentReferralIndication,
  continueMonitoring,
  considerReferral,
  referralRecommended,
  urgentProfessionalAssessment,
}

extension HealthReferralRecommendationLabel on HealthReferralRecommendation {
  String get label {
    switch (this) {
      case HealthReferralRecommendation.noCurrentReferralIndication:
        return 'NO CURRENT REFERRAL INDICATION';
      case HealthReferralRecommendation.continueMonitoring:
        return 'CONTINUE MONITORING';
      case HealthReferralRecommendation.considerReferral:
        return 'CONSIDER REFERRAL';
      case HealthReferralRecommendation.referralRecommended:
        return 'REFERRAL RECOMMENDED';
      case HealthReferralRecommendation.urgentProfessionalAssessment:
        return 'URGENT PROFESSIONAL ASSESSMENT';
    }
  }

  static HealthReferralRecommendation fromLabel(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.contains('urgent')) {
      return HealthReferralRecommendation.urgentProfessionalAssessment;
    }
    if (normalized.contains('recommended')) {
      return HealthReferralRecommendation.referralRecommended;
    }
    if (normalized.contains('consider')) {
      return HealthReferralRecommendation.considerReferral;
    }
    if (normalized.contains('monitor')) {
      return HealthReferralRecommendation.continueMonitoring;
    }
    return HealthReferralRecommendation.noCurrentReferralIndication;
  }
}

enum HealthDataQuality { complete, partial, needsVerification }

extension HealthDataQualityLabel on HealthDataQuality {
  String get label {
    switch (this) {
      case HealthDataQuality.complete:
        return 'COMPLETE';
      case HealthDataQuality.partial:
        return 'PARTIAL';
      case HealthDataQuality.needsVerification:
        return 'NEEDS VERIFICATION';
    }
  }

  static HealthDataQuality fromLabel(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.contains('verification') || normalized.contains('invalid')) {
      return HealthDataQuality.needsVerification;
    }
    if (normalized.contains('partial')) return HealthDataQuality.partial;
    return HealthDataQuality.complete;
  }
}

class HealthDataQualityIssue {
  const HealthDataQualityIssue({required this.field, required this.message});

  final String field;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'field': field,
    'message': message,
  };

  factory HealthDataQualityIssue.fromJson(Map<String, dynamic> json) {
    return HealthDataQualityIssue(
      field: json['field']?.toString() ?? 'record',
      message: json['message']?.toString() ?? 'Please verify this information.',
    );
  }
}

class HealthMeasurementFinding {
  const HealthMeasurementFinding({
    required this.measurementKey,
    required this.measurement,
    required this.recordedValue,
    required this.status,
    required this.reason,
    required this.suggestedAction,
    this.isInformational = false,
  });

  final String measurementKey;
  final String measurement;
  final String recordedValue;
  final HealthScreeningStatus status;
  final String reason;
  final String suggestedAction;
  final bool isInformational;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'measurement_key': measurementKey,
    'measurement': measurement,
    'recorded_value': recordedValue,
    'status': status.label,
    'reason': reason,
    'suggested_action': suggestedAction,
    'is_informational': isInformational,
  };

  factory HealthMeasurementFinding.fromJson(Map<String, dynamic> json) {
    return HealthMeasurementFinding(
      measurementKey: json['measurement_key']?.toString() ?? 'record',
      measurement: json['measurement']?.toString() ?? 'Health information',
      recordedValue: json['recorded_value']?.toString() ?? 'Not recorded',
      status: HealthScreeningStatusLabel.fromLabel(json['status']?.toString()),
      reason: json['reason']?.toString() ?? 'Review this information.',
      suggestedAction:
          json['suggested_action']?.toString() ??
          'Have authorized healthcare personnel review this information.',
      isInformational: json['is_informational'] == true,
    );
  }
}

class HealthScreeningResult {
  const HealthScreeningResult({
    required this.status,
    required this.dataQuality,
    required this.evaluatedMeasurements,
    required this.findings,
    required this.warnings,
    required this.referralRecommendation,
    required this.referralReasons,
    required this.suggestedAction,
    required this.missingInformation,
    required this.qualityIssues,
    required this.evaluatedAt,
    required this.ruleVersion,
    required this.requiresHumanReview,
    required this.source,
  });

  final HealthScreeningStatus status;
  final HealthDataQuality dataQuality;
  final List<String> evaluatedMeasurements;
  final List<HealthMeasurementFinding> findings;
  final List<String> warnings;
  final HealthReferralRecommendation referralRecommendation;
  final List<String> referralReasons;
  final String suggestedAction;
  final List<String> missingInformation;
  final List<HealthDataQualityIssue> qualityIssues;
  final DateTime evaluatedAt;
  final String ruleVersion;
  final bool requiresHumanReview;
  final String source;

  bool get hasActionableFinding => findings.any(
    (finding) =>
        !finding.isInformational &&
        finding.status.priority >=
            HealthScreeningStatus.needsAttention.priority,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.label,
    'data_quality': dataQuality.label,
    'evaluated_measurements': evaluatedMeasurements,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'warnings': warnings,
    'referral_recommendation': referralRecommendation.label,
    'referral_reasons': referralReasons,
    'suggested_action': suggestedAction,
    'missing_information': missingInformation,
    'quality_issues': qualityIssues.map((issue) => issue.toJson()).toList(),
    'evaluated_at': evaluatedAt.toUtc().toIso8601String(),
    'rule_version': ruleVersion,
    'requires_human_review': requiresHumanReview,
    'source': source,
  };

  factory HealthScreeningResult.fromJson(Map<String, dynamic> json) {
    final findingJson = _mapList(json['findings']);
    final issueJson = _mapList(json['quality_issues']);
    return HealthScreeningResult(
      status: HealthScreeningStatusLabel.fromLabel(json['status']?.toString()),
      dataQuality: HealthDataQualityLabel.fromLabel(
        json['data_quality']?.toString(),
      ),
      evaluatedMeasurements: _stringList(json['evaluated_measurements']),
      findings: findingJson
          .map(HealthMeasurementFinding.fromJson)
          .toList(growable: false),
      warnings: _stringList(json['warnings']),
      referralRecommendation: HealthReferralRecommendationLabel.fromLabel(
        json['referral_recommendation']?.toString(),
      ),
      referralReasons: _stringList(json['referral_reasons']),
      suggestedAction:
          json['suggested_action']?.toString() ??
          'Have authorized healthcare personnel review the screening result.',
      missingInformation: _stringList(json['missing_information']),
      qualityIssues: issueJson
          .map(HealthDataQualityIssue.fromJson)
          .toList(growable: false),
      evaluatedAt:
          DateTime.tryParse(json['evaluated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      ruleVersion:
          json['rule_version']?.toString() ?? HealthScreeningEngine.ruleVersion,
      requiresHumanReview: json['requires_human_review'] != false,
      source: json['source']?.toString() ?? 'deterministic_screening',
    );
  }
}

/// Summary of already-persisted screening results. It never re-evaluates raw
/// patient data, which keeps historical dashboards aligned with the result
/// reviewed at the time of the check-up.
class HealthScreeningInsightSummary {
  const HealthScreeningInsightSummary({
    required this.evaluatedScreenings,
    required this.withinExpectedRange,
    required this.needsAttention,
    required this.referralReview,
    required this.urgentFindings,
    required this.needsProfessionalReview,
    required this.dataQualityIssues,
    required this.referralRecommendations,
    required this.flaggedMeasurements,
  });

  final int evaluatedScreenings;
  final int withinExpectedRange;
  final int needsAttention;
  final int referralReview;
  final int urgentFindings;
  final int needsProfessionalReview;
  final int dataQualityIssues;
  final int referralRecommendations;
  final Map<String, int> flaggedMeasurements;

  bool get hasData => evaluatedScreenings > 0;

  static HealthScreeningInsightSummary fromRecords(
    Iterable<Map<String, dynamic>> records,
  ) {
    var evaluated = 0;
    var within = 0;
    var attention = 0;
    var referral = 0;
    var urgent = 0;
    var professionalReview = 0;
    var qualityIssues = 0;
    var recommendations = 0;
    final flaggedMeasurements = <String, int>{};

    for (final record in records) {
      final result = HealthScreeningEngine.resultFromRecord(record);
      if (result == null) continue;
      evaluated++;
      switch (result.status) {
        case HealthScreeningStatus.withinExpectedRange:
          within++;
        case HealthScreeningStatus.needsAttention:
          attention++;
        case HealthScreeningStatus.referralReview:
          referral++;
        case HealthScreeningStatus.urgentAssessment:
          urgent++;
        case HealthScreeningStatus.needsProfessionalReview:
          professionalReview++;
      }
      qualityIssues += result.qualityIssues.length;
      if (result.referralRecommendation.index >=
          HealthReferralRecommendation.considerReferral.index) {
        recommendations++;
      }
      for (final finding in result.findings) {
        if (finding.isInformational ||
            finding.status.priority <
                HealthScreeningStatus.needsAttention.priority) {
          continue;
        }
        final key = finding.measurement;
        flaggedMeasurements[key] = (flaggedMeasurements[key] ?? 0) + 1;
      }
    }

    return HealthScreeningInsightSummary(
      evaluatedScreenings: evaluated,
      withinExpectedRange: within,
      needsAttention: attention,
      referralReview: referral,
      urgentFindings: urgent,
      needsProfessionalReview: professionalReview,
      dataQualityIssues: qualityIssues,
      referralRecommendations: recommendations,
      flaggedMeasurements: Map<String, int>.unmodifiable(flaggedMeasurements),
    );
  }
}

/// A conservative rules engine based on WHO IITT emergency-triage guidance and
/// the American Heart Association adult blood-pressure categories. These rules
/// identify records for human review; they are not a diagnosis engine.
class HealthScreeningEngine {
  HealthScreeningEngine._();

  static const String ruleVersion = 'who-iitt-aha-screening-v1';
  static const String source = 'deterministic_screening';

  static HealthScreeningResult evaluate(
    Map<String, dynamic> healthData, {
    DateTime? evaluatedAt,
  }) {
    final text = _combinedText(healthData);
    final qualityIssues = <HealthDataQualityIssue>[];
    final missingInformation = <String>[];
    final findings = <HealthMeasurementFinding>[];
    final evaluatedMeasurements = <String>[];

    final ageInput = _readScalar(
      healthData,
      text,
      directKeys: const ['age', 'patientAge'],
      labels: const ['Age'],
      field: 'age',
      acceptedUnits: const <String>{'years', 'year', 'yr', 'yrs'},
    );
    _addIssueIfPresent(qualityIssues, ageInput);
    final age = _validScalar(ageInput, 0, 130, qualityIssues, 'age');
    if (age == null) {
      missingInformation.add(
        'Age is not recorded; age-specific screening may be limited.',
      );
    }

    final bp = _readBloodPressure(healthData, text);
    qualityIssues.addAll(bp.issues);
    if (bp.hasValue) {
      evaluatedMeasurements.add('Blood pressure');
      _evaluateBloodPressure(bp, healthData, text, findings);
    }

    final temperature = _readScalar(
      healthData,
      text,
      directKeys: const ['temperature', 'temp', 'bodyTemperature'],
      labels: const ['Temperature', 'Temp'],
      field: 'temperature',
      acceptedUnits: const <String>{'c', '°c', 'celsius'},
    );
    _addIssueIfPresent(qualityIssues, temperature);
    final temperatureValue = _validScalar(
      temperature,
      20,
      45,
      qualityIssues,
      'temperature',
    );
    if (temperatureValue != null) {
      evaluatedMeasurements.add('Temperature');
      _evaluateTemperature(temperatureValue, text, findings);
    }

    final heartRate = _readScalar(
      healthData,
      text,
      directKeys: const ['heartRate', 'heart_rate', 'pulse', 'hr'],
      labels: const ['Heart Rate', 'Pulse', 'HR'],
      field: 'heart_rate',
      acceptedUnits: const <String>{'bpm'},
    );
    _addIssueIfPresent(qualityIssues, heartRate);
    final heartRateValue = _validScalar(
      heartRate,
      20,
      250,
      qualityIssues,
      'heart_rate',
    );
    if (heartRateValue != null) {
      evaluatedMeasurements.add('Heart rate');
      _evaluateHeartRate(heartRateValue, age, findings, missingInformation);
    }

    final respiratoryRate = _readScalar(
      healthData,
      text,
      directKeys: const ['respiratoryRate', 'respiratory_rate', 'rr'],
      labels: const ['Respiratory Rate', 'RR'],
      field: 'respiratory_rate',
      acceptedUnits: const <String>{'brpm', 'bpm'},
    );
    _addIssueIfPresent(qualityIssues, respiratoryRate);
    final respiratoryRateValue = _validScalar(
      respiratoryRate,
      4,
      100,
      qualityIssues,
      'respiratory_rate',
    );
    if (respiratoryRateValue != null) {
      evaluatedMeasurements.add('Respiratory rate');
      _evaluateRespiratoryRate(
        respiratoryRateValue,
        age,
        findings,
        missingInformation,
      );
    }

    final oxygen = _readScalar(
      healthData,
      text,
      directKeys: const [
        'oxygenSaturation',
        'oxygen_saturation',
        'spo2',
        'oxygen',
        'o2',
      ],
      labels: const ['Oxygen Saturation', 'SpO2', 'Oxygen', 'O2'],
      field: 'oxygen_saturation',
      acceptedUnits: const <String>{'%', 'percent'},
    );
    _addIssueIfPresent(qualityIssues, oxygen);
    final oxygenValue = _validScalar(
      oxygen,
      50,
      100,
      qualityIssues,
      'oxygen_saturation',
    );
    if (oxygenValue != null) {
      evaluatedMeasurements.add('Oxygen saturation');
      _evaluateOxygen(oxygenValue, text, findings);
    }

    final weight = _readScalar(
      healthData,
      text,
      directKeys: const ['weight', 'weightKg', 'weight_kg'],
      labels: const ['Weight'],
      field: 'weight',
      acceptedUnits: const <String>{'kg', 'kilogram', 'kilograms'},
    );
    final height = _readScalar(
      healthData,
      text,
      directKeys: const ['height', 'heightCm', 'height_cm'],
      labels: const ['Height'],
      field: 'height',
      acceptedUnits: const <String>{'cm', 'centimeter', 'centimeters'},
    );
    _addIssueIfPresent(qualityIssues, weight);
    _addIssueIfPresent(qualityIssues, height);
    final weightValue = _validScalar(weight, 1, 400, qualityIssues, 'weight');
    final heightValue = _validScalar(height, 30, 250, qualityIssues, 'height');
    if (weightValue != null && heightValue != null && heightValue > 0) {
      evaluatedMeasurements.add('BMI context');
      final heightMeters = heightValue / 100;
      final bmi = weightValue / (heightMeters * heightMeters);
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'bmi_context',
          measurement: 'BMI context',
          recordedValue: bmi.toStringAsFixed(1),
          status: HealthScreeningStatus.withinExpectedRange,
          reason:
              'BMI was calculated for context only; interpretation requires age- and pregnancy-appropriate professional guidance.',
          suggestedAction:
              'Use the recorded height and weight with the standard health-service assessment.',
          isInformational: true,
        ),
      );
    }

    final pregnancy = _pregnancyContext(healthData, text);
    if (pregnancy == true) {
      _evaluatePregnancy(text, bp, findings);
    }

    _evaluateSymptomWarnings(text, findings);

    final hasSupportedValue = evaluatedMeasurements.isNotEmpty;
    if (!hasSupportedValue && text.trim().isEmpty) {
      missingInformation.add(
        'No supported vital signs or symptom information is recorded.',
      );
    } else if (!hasSupportedValue && text.trim().isNotEmpty) {
      missingInformation.add(
        'The recorded information did not contain a supported vital sign value.',
      );
    }

    final hasUrgent = findings.any(
      (finding) => finding.status == HealthScreeningStatus.urgentAssessment,
    );
    final hasReferral = findings.any(
      (finding) => finding.status == HealthScreeningStatus.referralReview,
    );
    final hasAttention = findings.any(
      (finding) => finding.status == HealthScreeningStatus.needsAttention,
    );
    final hasProfessionalReview = findings.any(
      (finding) =>
          finding.status == HealthScreeningStatus.needsProfessionalReview,
    );
    final actionableFindings = findings
        .where(
          (finding) =>
              !finding.isInformational &&
              finding.status.priority >=
                  HealthScreeningStatus.needsAttention.priority,
        )
        .toList(growable: false);

    HealthScreeningStatus status;
    if (hasUrgent) {
      status = HealthScreeningStatus.urgentAssessment;
    } else if (hasReferral || actionableFindings.length >= 2) {
      status = HealthScreeningStatus.referralReview;
    } else if (hasProfessionalReview ||
        (qualityIssues.isNotEmpty && !hasSupportedValue)) {
      status = HealthScreeningStatus.needsProfessionalReview;
    } else if (hasAttention) {
      status = HealthScreeningStatus.needsAttention;
    } else {
      status = HealthScreeningStatus.withinExpectedRange;
    }

    if (qualityIssues.isNotEmpty && !hasSupportedValue) {
      missingInformation.add(
        'Verify the flagged data-quality fields before use.',
      );
    }

    final dataQuality = qualityIssues.isNotEmpty
        ? HealthDataQuality.needsVerification
        : missingInformation.isNotEmpty
        ? HealthDataQuality.partial
        : HealthDataQuality.complete;

    final referralRecommendation = _referralRecommendation(
      status,
      hasAttention: hasAttention,
      hasReferral: hasReferral,
      hasUrgent: hasUrgent,
    );
    final referralReasons = actionableFindings
        .map((finding) => '${finding.measurement}: ${finding.reason}')
        .toList(growable: false);
    final warnings = actionableFindings
        .map(
          (finding) =>
              '${finding.measurement}: ${finding.recordedValue} — ${finding.reason}',
        )
        .toList();

    final suggestedAction = _suggestedAction(
      status,
      dataQuality,
      hasSupportedValue,
    );
    if (status == HealthScreeningStatus.withinExpectedRange &&
        warnings.isEmpty &&
        hasSupportedValue) {
      warnings.add(
        'No screening warning identified from the currently recorded measurements.',
      );
    }

    return HealthScreeningResult(
      status: status,
      dataQuality: dataQuality,
      evaluatedMeasurements: List<String>.unmodifiable(evaluatedMeasurements),
      findings: List<HealthMeasurementFinding>.unmodifiable(findings),
      warnings: List<String>.unmodifiable(warnings),
      referralRecommendation: referralRecommendation,
      referralReasons: List<String>.unmodifiable(referralReasons),
      suggestedAction: suggestedAction,
      missingInformation: List<String>.unmodifiable(missingInformation),
      qualityIssues: List<HealthDataQualityIssue>.unmodifiable(qualityIssues),
      evaluatedAt: (evaluatedAt ?? DateTime.now()).toUtc(),
      ruleVersion: ruleVersion,
      requiresHumanReview: true,
      source: source,
    );
  }

  /// Adds the structured screening result to the existing recovery-plan map.
  /// Older fields are preserved, and no database column is required.
  static Map<String, dynamic> attachToRecord(
    Map<String, dynamic> record,
    HealthScreeningResult result,
  ) {
    final next = Map<String, dynamic>.from(record);
    final plan = recoveryPlanFromRecord(record);
    plan['structured_screening'] = result.toJson();
    next['ai_recovery_plan'] = plan;
    next['ai_screening_status'] = result.status.label;
    next['ai_screening_rule_version'] = result.ruleVersion;
    next['ai_referral_recommendation'] = result.referralRecommendation.label;
    return next;
  }

  static Map<String, dynamic> recoveryPlanFromRecord(
    Map<String, dynamic> record,
  ) {
    dynamic raw = record['ai_recovery_plan'];
    if (raw is String && raw.trim().isNotEmpty) {
      raw = _tryDecodeMap(raw);
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static HealthScreeningResult? resultFromRecord(Map<String, dynamic> record) {
    dynamic raw = record['ai_screening'];
    if (raw is String && raw.trim().isNotEmpty) {
      raw = _tryDecodeMap(raw);
    }
    if (raw is Map) {
      return HealthScreeningResult.fromJson(Map<String, dynamic>.from(raw));
    }

    raw = recoveryPlanFromRecord(record)['structured_screening'];
    if (raw is String && raw.trim().isNotEmpty) {
      raw = _tryDecodeMap(raw);
    }
    if (raw is Map) {
      return HealthScreeningResult.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static void _evaluateBloodPressure(
    _BloodPressureInput bp,
    Map<String, dynamic> data,
    String text,
    List<HealthMeasurementFinding> findings,
  ) {
    final systolic = bp.systolic!;
    final diastolic = bp.diastolic!;
    final pregnant = _pregnancyContext(data, text) == true;
    final concerningSymptoms = _containsAnyConcern(text, const [
      'chest pain',
      'chest pressure',
      'shortness of breath',
      'difficulty breathing',
      'weakness',
      'numbness',
      'vision change',
      'difficulty speaking',
      'back pain',
    ]);
    final recorded =
        '${_formatNumber(systolic)}/${_formatNumber(diastolic)} mmHg';

    if ((pregnant && (systolic >= 160 || diastolic >= 110)) ||
        ((systolic > 180 || diastolic > 120) && concerningSymptoms)) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'blood_pressure',
          measurement: 'Blood pressure',
          recordedValue: recorded,
          status: HealthScreeningStatus.urgentAssessment,
          reason: pregnant
              ? 'The recorded blood pressure meets a high-risk pregnancy screening threshold.'
              : 'The recorded blood pressure is above the severe range and concerning symptoms were also reported.',
          suggestedAction:
              'Escalate for urgent in-person assessment by authorized healthcare personnel.',
        ),
      );
      return;
    }

    if (systolic > 180 ||
        diastolic > 120 ||
        (pregnant && (systolic >= 140 || diastolic >= 90))) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'blood_pressure',
          measurement: 'Blood pressure',
          recordedValue: recorded,
          status: HealthScreeningStatus.referralReview,
          reason: pregnant
              ? 'The recorded blood pressure is elevated in a pregnancy context and requires professional review.'
              : 'The recorded measurement is above the severe blood-pressure range and should be reviewed by a healthcare professional.',
          suggestedAction:
              'Repeat or verify the measurement and consider timely professional assessment.',
        ),
      );
      return;
    }

    if (systolic >= 140 || diastolic >= 90) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'blood_pressure',
          measurement: 'Blood pressure',
          recordedValue: recorded,
          status: HealthScreeningStatus.needsAttention,
          reason:
              'The recorded measurement is in a high blood-pressure category and should be reviewed in context.',
          suggestedAction:
              'Verify the reading and continue the standard health-service review.',
        ),
      );
    } else if (systolic >= 130 || diastolic >= 80) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'blood_pressure',
          measurement: 'Blood pressure',
          recordedValue: recorded,
          status: HealthScreeningStatus.needsAttention,
          reason:
              'The recorded measurement is above the normal adult blood-pressure category.',
          suggestedAction:
              'Verify the reading and discuss continued monitoring with authorized healthcare personnel.',
        ),
      );
    } else {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'blood_pressure',
          measurement: 'Blood pressure',
          recordedValue: recorded,
          status: HealthScreeningStatus.withinExpectedRange,
          reason:
              'The recorded measurement is within the adult screening category used by this engine.',
          suggestedAction: 'Continue the standard health-service workflow.',
        ),
      );
    }
  }

  static void _evaluateTemperature(
    double value,
    String text,
    List<HealthMeasurementFinding> findings,
  ) {
    final recorded = '${_formatNumber(value)} °C';
    if (value < 36 || value > 39) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'temperature',
          measurement: 'Temperature',
          recordedValue: recorded,
          status: HealthScreeningStatus.referralReview,
          reason:
              'The recorded temperature is outside the WHO high-risk screening range.',
          suggestedAction:
              'Verify the measurement and arrange professional review, considering the person’s symptoms and age.',
        ),
      );
    } else if (value >= 38) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'temperature',
          measurement: 'Temperature',
          recordedValue: recorded,
          status: HealthScreeningStatus.needsAttention,
          reason:
              'The recorded temperature is in a fever range and should be interpreted with the person’s symptoms and context.',
          suggestedAction:
              'Verify the measurement and review the reported symptoms.',
        ),
      );
    } else {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'temperature',
          measurement: 'Temperature',
          recordedValue: recorded,
          status: HealthScreeningStatus.withinExpectedRange,
          reason: 'The recorded temperature is within the screening range.',
          suggestedAction: 'Continue the standard health-service workflow.',
        ),
      );
    }
  }

  static void _evaluateHeartRate(
    double value,
    double? age,
    List<HealthMeasurementFinding> findings,
    List<String> missingInformation,
  ) {
    final recorded = '${_formatNumber(value)} bpm';
    if (age == null) {
      missingInformation.add(
        'Age is needed to interpret the heart-rate reading safely.',
      );
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'heart_rate',
          measurement: 'Heart rate',
          recordedValue: recorded,
          status: HealthScreeningStatus.needsProfessionalReview,
          reason:
              'Heart-rate interpretation depends on age and clinical context.',
          suggestedAction:
              'Verify the age and have authorized healthcare personnel review the reading.',
        ),
      );
      return;
    }
    if (age < 12) {
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'heart_rate',
          measurement: 'Heart rate',
          recordedValue: recorded,
          status: HealthScreeningStatus.needsProfessionalReview,
          reason:
              'This engine does not apply an adult heart-rate threshold to children.',
          suggestedAction:
              'Have authorized healthcare personnel interpret the pediatric reading using the appropriate protocol.',
        ),
      );
      return;
    }
    final status = value < 50 || value > 150
        ? HealthScreeningStatus.urgentAssessment
        : value < 60 || value > 130
        ? HealthScreeningStatus.referralReview
        : HealthScreeningStatus.withinExpectedRange;
    findings.add(
      HealthMeasurementFinding(
        measurementKey: 'heart_rate',
        measurement: 'Heart rate',
        recordedValue: recorded,
        status: status,
        reason: status == HealthScreeningStatus.withinExpectedRange
            ? 'The adult heart-rate reading is within the screening range.'
            : 'The adult heart-rate reading crosses a WHO high-risk screening threshold.',
        suggestedAction: status == HealthScreeningStatus.withinExpectedRange
            ? 'Continue the standard health-service workflow.'
            : 'Verify the reading and arrange professional review.',
      ),
    );
  }

  static void _evaluateRespiratoryRate(
    double value,
    double? age,
    List<HealthMeasurementFinding> findings,
    List<String> missingInformation,
  ) {
    if (age == null) {
      missingInformation.add(
        'Age is needed to interpret the respiratory-rate reading safely.',
      );
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'respiratory_rate',
          measurement: 'Respiratory rate',
          recordedValue: '${_formatNumber(value)} breaths/min',
          status: HealthScreeningStatus.needsProfessionalReview,
          reason:
              'Respiratory-rate thresholds differ by age and the age was not recorded.',
          suggestedAction:
              'Verify the age and have authorized healthcare personnel review the reading.',
        ),
      );
      return;
    }

    double low;
    double high;
    if (age < 1) {
      low = 25;
      high = 50;
    } else if (age < 5) {
      low = 20;
      high = 40;
    } else if (age < 12) {
      low = 10;
      high = 30;
    } else {
      low = 10;
      high = 30;
    }
    final outsideRange = value < low || value > high;
    final status = outsideRange
        ? HealthScreeningStatus.referralReview
        : HealthScreeningStatus.withinExpectedRange;
    findings.add(
      HealthMeasurementFinding(
        measurementKey: 'respiratory_rate',
        measurement: 'Respiratory rate',
        recordedValue: '${_formatNumber(value)} breaths/min',
        status: status,
        reason: outsideRange
            ? 'The reading is outside the age-specific WHO screening range used by this engine.'
            : 'The reading is within the age-specific screening range.',
        suggestedAction: outsideRange
            ? 'Verify the reading and arrange professional review, considering reported breathing symptoms.'
            : 'Continue the standard health-service workflow.',
      ),
    );
  }

  static void _evaluateOxygen(
    double value,
    String text,
    List<HealthMeasurementFinding> findings,
  ) {
    final status = value < 92
        ? _containsAnyConcern(text, const [
                'shortness of breath',
                'difficulty breathing',
                'cannot breathe',
                "can't breathe",
              ])
              ? HealthScreeningStatus.urgentAssessment
              : HealthScreeningStatus.referralReview
        : HealthScreeningStatus.withinExpectedRange;
    findings.add(
      HealthMeasurementFinding(
        measurementKey: 'oxygen_saturation',
        measurement: 'Oxygen saturation',
        recordedValue: '${_formatNumber(value)}%',
        status: status,
        reason: value < 92
            ? 'The recorded oxygen saturation is below the WHO high-risk screening threshold.'
            : 'The recorded oxygen saturation is within the screening range.',
        suggestedAction: value < 92
            ? 'Verify the reading and arrange professional assessment; escalate urgently if breathing difficulty is present.'
            : 'Continue the standard health-service workflow.',
      ),
    );
  }

  static void _evaluatePregnancy(
    String text,
    _BloodPressureInput bp,
    List<HealthMeasurementFinding> findings,
  ) {
    final pregnancyConcern = _containsAnyConcern(text, const [
      'heavy bleeding',
      'vaginal bleeding',
      'severe abdominal pain',
      'severe headache',
      'visual changes',
      'blurred vision',
      'convulsion',
      'seizure',
      'active labor',
    ]);
    if (!pregnancyConcern) return;
    final bpConcern =
        bp.systolic != null &&
        bp.diastolic != null &&
        (bp.systolic! >= 160 || bp.diastolic! >= 110);
    findings.add(
      HealthMeasurementFinding(
        measurementKey: 'pregnancy_context',
        measurement: 'Pregnancy warning signs',
        recordedValue: 'Reported in record',
        status: HealthScreeningStatus.urgentAssessment,
        reason: bpConcern
            ? 'A pregnancy warning sign was reported together with a high-risk blood-pressure reading.'
            : 'A pregnancy warning sign was reported in the record.',
        suggestedAction:
            'Escalate for urgent in-person assessment by authorized healthcare personnel.',
      ),
    );
  }

  static void _evaluateSymptomWarnings(
    String text,
    List<HealthMeasurementFinding> findings,
  ) {
    const urgentSymptoms = <String>[
      'unresponsive',
      'not breathing',
      'cannot breathe',
      "can't breathe",
      'severe difficulty breathing',
      'severe chest pain',
      'uncontrolled bleeding',
      'heavy bleeding',
      'active convulsion',
      'active seizure',
      'blue lips',
    ];
    for (final symptom in urgentSymptoms) {
      if (!_containsConcern(text, symptom)) continue;
      findings.add(
        HealthMeasurementFinding(
          measurementKey: 'symptoms',
          measurement: 'Reported warning signs',
          recordedValue: symptom,
          status: HealthScreeningStatus.urgentAssessment,
          reason:
              'The record contains a symptom that requires urgent professional assessment.',
          suggestedAction:
              'Escalate for urgent in-person assessment by authorized healthcare personnel.',
        ),
      );
      break;
    }
  }

  static HealthReferralRecommendation _referralRecommendation(
    HealthScreeningStatus status, {
    required bool hasAttention,
    required bool hasReferral,
    required bool hasUrgent,
  }) {
    if (hasUrgent || status == HealthScreeningStatus.urgentAssessment) {
      return HealthReferralRecommendation.urgentProfessionalAssessment;
    }
    if (hasReferral || status == HealthScreeningStatus.referralReview) {
      return HealthReferralRecommendation.referralRecommended;
    }
    if (hasAttention || status == HealthScreeningStatus.needsAttention) {
      return HealthReferralRecommendation.considerReferral;
    }
    if (status == HealthScreeningStatus.needsProfessionalReview) {
      return HealthReferralRecommendation.continueMonitoring;
    }
    return HealthReferralRecommendation.noCurrentReferralIndication;
  }

  static String _suggestedAction(
    HealthScreeningStatus status,
    HealthDataQuality quality,
    bool hasSupportedValue,
  ) {
    if (quality == HealthDataQuality.needsVerification) {
      return 'Verify the flagged data-quality fields before relying on this screening result.';
    }
    switch (status) {
      case HealthScreeningStatus.urgentAssessment:
        return 'Escalate for urgent in-person assessment by authorized healthcare personnel.';
      case HealthScreeningStatus.referralReview:
        return 'Review the findings and consider using the existing referral workflow.';
      case HealthScreeningStatus.needsAttention:
        return 'Verify the readings and continue the standard health-service review.';
      case HealthScreeningStatus.needsProfessionalReview:
        return hasSupportedValue
            ? 'Have authorized healthcare personnel review the context before acting.'
            : 'Complete or verify the available information, then have authorized healthcare personnel review it.';
      case HealthScreeningStatus.withinExpectedRange:
        return 'Continue the standard health-service workflow; this screening result does not replace professional judgment.';
    }
  }

  static String _combinedText(Map<String, dynamic> data) {
    final values = <String>[];
    for (final key in const [
      'vitalsigns',
      'vitalSigns',
      'vitals',
      'vital_signs',
      'details',
      'symptoms',
      'clinicalObservations',
      'observations',
      'riskLevel',
      'pregnancyStatus',
      'pregnant',
    ]) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        values.add(value.toString());
      }
    }
    return values.join(' | ');
  }

  static bool? _pregnancyContext(Map<String, dynamic> data, String text) {
    for (final key in const ['pregnant', 'isPregnant']) {
      final value = data[key];
      if (value is bool) return value;
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'pregnant') {
        return true;
      }
      if (normalized == 'false' ||
          normalized == 'no' ||
          normalized == 'not pregnant') {
        return false;
      }
    }
    final status =
        data['pregnancyStatus']?.toString().trim().toLowerCase() ?? '';
    if (status.contains('pregnant')) return true;
    if (status.contains('not pregnant')) return false;
    if (_containsConcern(text, 'pregnant') ||
        _containsConcern(text, 'prenatal')) {
      return true;
    }
    return null;
  }

  static _ScalarInput _readScalar(
    Map<String, dynamic> data,
    String text, {
    required List<String> directKeys,
    required List<String> labels,
    required String field,
    required Set<String> acceptedUnits,
  }) {
    dynamic raw;
    for (final key in directKeys) {
      if (!data.containsKey(key)) continue;
      final candidate = data[key];
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        raw = candidate;
        break;
      }
    }
    var supplied = raw != null;
    if (!supplied) {
      final segment = _labeledSegment(text, labels);
      if (segment.present) {
        raw = segment.value;
        supplied = true;
      }
    }
    if (!supplied) return const _ScalarInput();
    final parsed = _parseNumber(raw, acceptedUnits);
    if (parsed.value == null) {
      return _ScalarInput(
        supplied: true,
        issue: HealthDataQualityIssue(
          field: field,
          message: 'Please verify the entered $field value and unit.',
        ),
      );
    }
    return _ScalarInput(
      supplied: true,
      value: parsed.value,
      issue: parsed.issue,
    );
  }

  static _BloodPressureInput _readBloodPressure(
    Map<String, dynamic> data,
    String text,
  ) {
    dynamic raw;
    for (final key in const [
      'bloodPressure',
      'blood_pressure',
      'bp',
      'bloodPressureReading',
    ]) {
      if (!data.containsKey(key)) continue;
      final candidate = data[key];
      if (candidate is Map) {
        final sys = _asNumber(candidate['systolic']);
        final dia = _asNumber(candidate['diastolic']);
        if (sys != null || dia != null) {
          return _validateBloodPressure(sys, dia);
        }
      }
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        raw = candidate;
        break;
      }
    }
    if (raw == null) {
      final segment = _labeledSegment(text, const ['Blood Pressure', 'BP']);
      if (segment.present) raw = segment.value;
    }
    if (raw == null) {
      final sys = _readScalar(
        data,
        text,
        directKeys: const ['systolic', 'systolicBp', 'systolicBP'],
        labels: const ['Systolic'],
        field: 'systolic',
        acceptedUnits: const <String>{'mmhg'},
      );
      final dia = _readScalar(
        data,
        text,
        directKeys: const ['diastolic', 'diastolicBp', 'diastolicBP'],
        labels: const ['Diastolic'],
        field: 'diastolic',
        acceptedUnits: const <String>{'mmhg'},
      );
      if (sys.value != null ||
          dia.value != null ||
          sys.issue != null ||
          dia.issue != null) {
        return _validateBloodPressure(
          sys.value,
          dia.value,
          issues: <HealthDataQualityIssue>[
            if (sys.issue != null) sys.issue!,
            if (dia.issue != null) dia.issue!,
          ],
        );
      }
      return const _BloodPressureInput();
    }
    final parsed = _parseBloodPressure(raw);
    if (parsed == null) {
      return _BloodPressureInput(
        supplied: true,
        issues: const <HealthDataQualityIssue>[
          HealthDataQualityIssue(
            field: 'blood_pressure',
            message:
                'Please verify the blood-pressure format, for example 120/80 mmHg.',
          ),
        ],
      );
    }
    return _validateBloodPressure(parsed.$1, parsed.$2);
  }

  static _BloodPressureInput _validateBloodPressure(
    double? systolic,
    double? diastolic, {
    List<HealthDataQualityIssue> issues = const <HealthDataQualityIssue>[],
  }) {
    final nextIssues = <HealthDataQualityIssue>[...issues];
    if (systolic == null ||
        diastolic == null ||
        systolic < 40 ||
        systolic > 300 ||
        diastolic < 20 ||
        diastolic > 200 ||
        systolic <= diastolic) {
      nextIssues.add(
        const HealthDataQualityIssue(
          field: 'blood_pressure',
          message: 'Please verify the blood-pressure values and format.',
        ),
      );
      return _BloodPressureInput(
        supplied: true,
        issues: List<HealthDataQualityIssue>.unmodifiable(nextIssues),
      );
    }
    return _BloodPressureInput(
      supplied: true,
      systolic: systolic,
      diastolic: diastolic,
      issues: List<HealthDataQualityIssue>.unmodifiable(nextIssues),
    );
  }

  static void _addIssueIfPresent(
    List<HealthDataQualityIssue> issues,
    _ScalarInput input,
  ) {
    if (input.issue != null) issues.add(input.issue!);
  }

  static double? _validScalar(
    _ScalarInput input,
    double minimum,
    double maximum,
    List<HealthDataQualityIssue> issues,
    String field,
  ) {
    final value = input.value;
    if (value == null || input.issue != null) return null;
    if (value < minimum || value > maximum) {
      issues.add(
        HealthDataQualityIssue(
          field: field,
          message: 'Please verify the entered $field value.',
        ),
      );
      return null;
    }
    return value;
  }

  static _ParsedNumber _parseNumber(dynamic raw, Set<String> acceptedUnits) {
    if (raw is num) return _ParsedNumber(raw.toDouble());
    final value = raw?.toString().trim() ?? '';
    final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*([^\d]*)$').firstMatch(value);
    if (match == null) return const _ParsedNumber(null);
    final number = double.tryParse(match.group(1)!);
    if (number == null) return const _ParsedNumber(null);
    final unit = match.group(2)!.trim().toLowerCase();
    if (unit.isNotEmpty && !acceptedUnits.contains(unit)) {
      return _ParsedNumber(
        number,
        HealthDataQualityIssue(
          field: 'measurement',
          message: 'Please verify the measurement unit.',
        ),
      );
    }
    return _ParsedNumber(number);
  }

  static (double, double)? _parseBloodPressure(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    final match = RegExp(
      r'^(-?\d+(?:\.\d+)?)\s*/\s*(-?\d+(?:\.\d+)?)(?:\s*(?:mmhg)?)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final systolic = double.tryParse(match.group(1)!);
    final diastolic = double.tryParse(match.group(2)!);
    if (systolic == null || diastolic == null) return null;
    return (systolic, diastolic);
  }

  static _LabeledSegment _labeledSegment(String text, List<String> labels) {
    if (text.trim().isEmpty) return const _LabeledSegment();
    final labelPattern = labels.map(RegExp.escape).join('|');
    final match = RegExp(
      r'(?:^|[,|;\n])\s*(?:' + labelPattern + r')\s*[:=-]?\s*([^,|;\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null
        ? const _LabeledSegment()
        : _LabeledSegment(present: true, value: match.group(1)?.trim());
  }

  static double? _asNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  static bool _containsAnyConcern(String text, List<String> terms) {
    return terms.any((term) => _containsConcern(text, term));
  }

  static bool _containsConcern(String text, String term) {
    final normalized = text.toLowerCase();
    final index = normalized.indexOf(term.toLowerCase());
    if (index < 0) return false;
    final preceding = normalized.substring(index > 20 ? index - 20 : 0, index);
    if (RegExp(r'\b(no|not|without|denies|denied)\s*$').hasMatch(preceding)) {
      return false;
    }
    return true;
  }

  static dynamic _tryDecodeMap(String value) {
    try {
      return value.isEmpty ? null : jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
}

class _ScalarInput {
  const _ScalarInput({this.supplied = false, this.value, this.issue});

  final bool supplied;
  final double? value;
  final HealthDataQualityIssue? issue;
}

class _ParsedNumber {
  const _ParsedNumber(this.value, [this.issue]);

  final double? value;
  final HealthDataQualityIssue? issue;
}

class _LabeledSegment {
  const _LabeledSegment({this.present = false, this.value});

  final bool present;
  final String? value;
}

class _BloodPressureInput {
  const _BloodPressureInput({
    this.supplied = false,
    this.systolic,
    this.diastolic,
    this.issues = const <HealthDataQualityIssue>[],
  });

  final bool supplied;
  final double? systolic;
  final double? diastolic;
  final List<HealthDataQualityIssue> issues;

  bool get hasValue => systolic != null && diastolic != null;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
