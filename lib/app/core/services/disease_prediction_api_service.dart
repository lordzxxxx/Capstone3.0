import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef AiSecurityHeadersProvider = Future<Map<String, String>> Function();

Future<Map<String, String>> _firebaseSecurityHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Sign in before requesting symptom guidance.');
  }
  final idToken = await user.getIdToken();
  final appCheckToken = await FirebaseAppCheck.instance.getToken();
  if (idToken == null || idToken.isEmpty) {
    throw StateError('Could not obtain a Firebase sign-in token.');
  }
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw StateError('Could not verify this application with App Check.');
  }
  return {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
    'X-Firebase-AppCheck': appCheckToken,
  };
}

class DiseasePredictionApiException implements Exception {
  const DiseasePredictionApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DiseasePredictionApiService {
  DiseasePredictionApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
  );

  final http.Client _client;

  static String _defaultBaseUrl() {
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return _configuredBaseUrl.trim();
    }
    // Never let a release build silently call a developer's localhost. The
    // deployment pipeline must provide the real HTTPS API with
    // --dart-define=AI_API_BASE_URL=...; the check-up flow catches the empty
    // value and continues saving the record without remote guidance.
    if (kReleaseMode) return '';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static List<String> parseSymptoms(String input) {
    final seen = <String>{};
    final symptoms = <String>[];
    for (final value in input.split(RegExp(r'[,;\n]+'))) {
      final symptom = value.trim();
      if (symptom.isNotEmpty && seen.add(symptom.toLowerCase())) {
        symptoms.add(symptom);
      }
    }
    return symptoms;
  }

  Future<DiseasePredictionResult> predictFromText(String symptomText) async {
    final symptoms = parseSymptoms(symptomText);
    if (symptoms.isEmpty) {
      throw const DiseasePredictionApiException(
        'Enter at least one symptom before requesting an AI prediction.',
      );
    }

    throw const DiseasePredictionApiException(
      'Disease prediction has been disabled. Use AI Symptom Guidance instead.',
    );

    /* Legacy implementation intentionally unreachable while old response
       models remain available for reading previously saved records.
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/predict'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'symptoms': symptoms}),
          )
          .timeout(const Duration(seconds: 20));

      final body = _decodeObject(response.body);
      if (response.statusCode != 200) {
        final detail = body['detail']?.toString().trim();
        final message = body['message']?.toString().trim();
        throw DiseasePredictionApiException(
          detail?.isNotEmpty == true
              ? detail!
              : message?.isNotEmpty == true
              ? message!
              : 'Prediction service returned HTTP ${response.statusCode}.',
        );
      }
      return DiseasePredictionResult.fromJson(body);
    } on TimeoutException {
      throw const DiseasePredictionApiException(
        'The AI prediction service timed out. The record can still be saved.',
      );
    } on DiseasePredictionApiException {
      rethrow;
    } on FormatException {
      throw const DiseasePredictionApiException(
        'The AI prediction service returned an invalid response.',
      );
    } on http.ClientException {
      throw DiseasePredictionApiException(
        'Cannot reach the AI prediction service at $_baseUrl.',
      );
    } catch (_) {
      throw const DiseasePredictionApiException(
        'AI prediction is temporarily unavailable.',
      );
    } */
  }

  static Map<String, dynamic> _decodeObject(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void close() => _client.close();
}

class SymptomGuidanceApiException implements Exception {
  const SymptomGuidanceApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SymptomGuidanceApiService {
  SymptomGuidanceApiService({
    http.Client? client,
    String? baseUrl,
    AiSecurityHeadersProvider? securityHeadersProvider,
  }) : _client = client ?? http.Client(),
       _securityHeadersProvider =
           securityHeadersProvider ?? _firebaseSecurityHeaders,
       _baseUrl = (baseUrl ?? DiseasePredictionApiService._defaultBaseUrl())
           .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;
  final AiSecurityHeadersProvider _securityHeadersProvider;

  Future<SymptomGuidanceResult> getGuidanceFromText(String symptomText) async {
    final symptoms = DiseasePredictionApiService.parseSymptoms(symptomText);
    if (symptoms.isEmpty) {
      throw const SymptomGuidanceApiException(
        'Enter at least one symptom before requesting symptom guidance.',
      );
    }
    if (_baseUrl.isEmpty) {
      throw const SymptomGuidanceApiException(
        'Symptom guidance is not configured for this release. The record can still be saved.',
      );
    }
    try {
      final headers = await _securityHeadersProvider();
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/guidance'),
            headers: headers,
            body: jsonEncode({'symptoms': symptoms}),
          )
          .timeout(const Duration(seconds: 20));
      final body = DiseasePredictionApiService._decodeObject(response.body);
      if (response.statusCode != 200) {
        final detail = body['detail']?.toString().trim();
        final message = body['message']?.toString().trim();
        throw SymptomGuidanceApiException(
          detail?.isNotEmpty == true
              ? detail!
              : message?.isNotEmpty == true
              ? message!
              : 'Symptom guidance service returned HTTP ${response.statusCode}.',
        );
      }
      return SymptomGuidanceResult.fromJson(body);
    } on TimeoutException {
      throw const SymptomGuidanceApiException(
        'The symptom guidance service timed out. The record can still be saved.',
      );
    } on SymptomGuidanceApiException {
      rethrow;
    } on StateError catch (error) {
      throw SymptomGuidanceApiException(error.message.toString());
    } on FormatException {
      throw const SymptomGuidanceApiException(
        'The symptom guidance service returned an invalid response.',
      );
    } on http.ClientException {
      throw SymptomGuidanceApiException(
        'Cannot reach the symptom guidance service at $_baseUrl.',
      );
    } catch (_) {
      throw const SymptomGuidanceApiException(
        'Symptom guidance is temporarily unavailable.',
      );
    }
  }

  void close() => _client.close();
}

class SymptomGuidanceResult {
  const SymptomGuidanceResult({
    required this.recognizedSymptoms,
    required this.recognizedConditions,
    required this.ignoredSymptoms,
    required this.matchedGuidanceSymptoms,
    required this.missingGuidanceSymptoms,
    required this.matchedGuidanceConditions,
    required this.missingGuidanceConditions,
    required this.homeCare,
    required this.precautions,
    required this.whenToSeekCare,
    required this.emergencyWarningSigns,
    required this.references,
    required this.contentAvailable,
    required this.disclaimer,
    required this.suggestedHealthCategory,
    required this.categoryBasis,
    required this.categoryRequiresReview,
    required this.categoryRuleVersion,
    required this.categoryMatchedConditions,
    required this.categoryUnmappedConditions,
    required this.categoryMatchedSymptoms,
    required this.categoryUnmappedSymptoms,
  });

  factory SymptomGuidanceResult.fromJson(Map<String, dynamic> json) {
    return SymptomGuidanceResult(
      recognizedSymptoms: _strings(json['recognizedSymptoms']),
      recognizedConditions: _strings(json['recognizedConditions']),
      ignoredSymptoms: _strings(json['ignoredSymptoms']),
      matchedGuidanceSymptoms: _strings(json['matchedGuidanceSymptoms']),
      missingGuidanceSymptoms: _strings(json['missingGuidanceSymptoms']),
      matchedGuidanceConditions: _strings(json['matchedGuidanceConditions']),
      missingGuidanceConditions: _strings(json['missingGuidanceConditions']),
      homeCare: _strings(json['homeCare']),
      precautions: _strings(json['precautions']),
      whenToSeekCare: _strings(json['whenToSeekCare']),
      emergencyWarningSigns: _strings(json['emergencyWarningSigns']),
      references: _maps(json['references']),
      contentAvailable: json['contentAvailable'] == true,
      disclaimer: _nullableString(json['disclaimer']) ?? '',
      suggestedHealthCategory:
          _nullableString(json['suggestedHealthCategory']) ??
          'Needs Clinical Review',
      categoryBasis: _nullableString(json['categoryBasis']) ?? 'symptom_only',
      categoryRequiresReview: json['categoryRequiresReview'] != false,
      categoryRuleVersion:
          _nullableString(json['categoryRuleVersion']) ??
          'condition-category-rules-v2',
      categoryMatchedConditions: _strings(json['categoryMatchedConditions']),
      categoryUnmappedConditions: _strings(json['categoryUnmappedConditions']),
      categoryMatchedSymptoms: _strings(json['categoryMatchedSymptoms']),
      categoryUnmappedSymptoms: _strings(json['categoryUnmappedSymptoms']),
    );
  }

  final List<String> recognizedSymptoms;
  final List<String> recognizedConditions;
  final List<String> ignoredSymptoms;
  final List<String> matchedGuidanceSymptoms;
  final List<String> missingGuidanceSymptoms;
  final List<String> matchedGuidanceConditions;
  final List<String> missingGuidanceConditions;
  final List<String> homeCare;
  final List<String> precautions;
  final List<String> whenToSeekCare;
  final List<String> emergencyWarningSigns;
  final List<Map<String, dynamic>> references;
  final bool contentAvailable;
  final String disclaimer;
  final String suggestedHealthCategory;
  final String categoryBasis;
  final bool categoryRequiresReview;
  final String categoryRuleVersion;
  final List<String> categoryMatchedConditions;
  final List<String> categoryUnmappedConditions;
  final List<String> categoryMatchedSymptoms;
  final List<String> categoryUnmappedSymptoms;

  // Compatibility accessors for existing record persistence code.
  String get category => 'Symptom Guidance';
  String get severity => emergencyWarningSigns.isEmpty
      ? 'Educational support'
      : 'Includes emergency warnings';
  double get confidence => 0;
  String get method => 'keyword_guidance';
  List<String> get keywords => [...recognizedSymptoms, ...recognizedConditions];
  Map<String, dynamic> get recoveryPlan =>
      Map<String, dynamic>.from(toRecordFields()['ai_recovery_plan'] as Map);

  Map<String, dynamic> toRecordFields() {
    return {
      'ai_category': 'Symptom Guidance',
      'ai_severity': emergencyWarningSigns.isEmpty
          ? 'Educational support'
          : 'Includes emergency warnings',
      'ai_method': 'keyword_guidance',
      'ai_keywords': [
        ...recognizedSymptoms,
        ...recognizedConditions,
      ].join(', '),
      'ai_suggested_health_category': suggestedHealthCategory,
      'ai_category_basis': categoryBasis,
      'ai_category_requires_review': categoryRequiresReview,
      'ai_category_rule_version': categoryRuleVersion,
      'ai_category_matched_conditions': categoryMatchedConditions,
      'ai_category_unmapped_conditions': categoryUnmappedConditions,
      'ai_category_matched_symptoms': categoryMatchedSymptoms,
      'ai_category_unmapped_symptoms': categoryUnmappedSymptoms,
      // Canonical fields used by check-up records and analytics. This is an
      // administrative keyword classification, not a medical diagnosis.
      'healthCategory': suggestedHealthCategory,
      'healthCategoryBasis': categoryBasis,
      'healthCategoryRequiresReview': categoryRequiresReview,
      'healthCategoryRuleVersion': categoryRuleVersion,
      'healthCategoryKeywords': [
        ...categoryMatchedConditions,
        ...categoryMatchedSymptoms,
      ],
      'diseaseType': suggestedHealthCategory,
      'ai_recovery_plan': {
        'home_care': homeCare,
        'precautions': [...precautions, ...emergencyWarningSigns],
        'general_advice': whenToSeekCare,
        'emergency_warning_signs': emergencyWarningSigns,
        'guidance_source': 'firestore_symptom_guidance',
        'matched_guidance_symptoms': matchedGuidanceSymptoms,
        'missing_guidance_symptoms': missingGuidanceSymptoms,
        'entered_conditions': recognizedConditions,
        'matched_guidance_conditions': matchedGuidanceConditions,
        'missing_guidance_conditions': missingGuidanceConditions,
        'references': references,
        'disclaimer': disclaimer,
        'decision_support': {
          'explanation':
              'This guidance was based on the symptoms and conditions recognized from the text entered for this request. It is educational decision support, not a final diagnosis or prescription.',
          'influencing_information': [
            if (recognizedSymptoms.isNotEmpty)
              'Recognized symptoms: ${recognizedSymptoms.join(', ')}',
            if (recognizedConditions.isNotEmpty)
              'Recognized conditions: ${recognizedConditions.join(', ')}',
          ],
          'risk_factors': emergencyWarningSigns.isEmpty
              ? [
                  'No emergency warning sign was returned for the recognized text',
                ]
              : ['Emergency warning signs were returned and require escalation'],
          'missing_information': [
            if (ignoredSymptoms.isNotEmpty)
              'Unrecognized or uncertain text: ${ignoredSymptoms.join(', ')}',
            if (missingGuidanceSymptoms.isNotEmpty)
              'No guidance was available for: ${missingGuidanceSymptoms.join(', ')}',
            if (recognizedSymptoms.isEmpty && recognizedConditions.isEmpty)
              'No recognized symptom or condition was available',
          ],
          'confidence': null,
          'requires_human_review': true,
          'next_action': emergencyWarningSigns.isEmpty
              ? 'Verify the complete record and have authorized healthcare personnel review the guidance before acting.'
              : 'Escalate possible emergency warning signs for urgent in-person assessment by authorized healthcare personnel.',
          'review_status': 'Pending human review',
          'final_human_decision': '',
          'human_review_note': '',
        },
      },
    };
  }
}

class DiseasePredictionResult {
  const DiseasePredictionResult({
    required this.prediction,
    required this.topPredictions,
    required this.recognizedSymptoms,
    required this.ignoredSymptoms,
    required this.diseaseInformation,
    required this.contentAvailable,
    required this.confidenceThresholdMet,
    required this.warning,
    required this.fallbackMessage,
    required this.disclaimer,
  });

  factory DiseasePredictionResult.fromJson(Map<String, dynamic> json) {
    final predictionJson = _map(json['prediction']);
    if (predictionJson == null) {
      throw const FormatException('Missing prediction.');
    }
    return DiseasePredictionResult(
      prediction: DiseasePrediction.fromJson(predictionJson),
      topPredictions: _maps(
        json['topPredictions'],
      ).map(DiseasePrediction.fromJson).toList(),
      recognizedSymptoms: _strings(json['recognizedSymptoms']),
      ignoredSymptoms: _strings(json['ignoredSymptoms']),
      diseaseInformation: _map(json['diseaseInformation']) == null
          ? null
          : DiseaseInformation.fromJson(_map(json['diseaseInformation'])!),
      contentAvailable: json['contentAvailable'] == true,
      confidenceThresholdMet: json['confidenceThresholdMet'] == true,
      warning: _nullableString(json['warning']),
      fallbackMessage: _nullableString(json['fallbackMessage']),
      disclaimer: _nullableString(json['disclaimer']) ?? '',
    );
  }

  final DiseasePrediction prediction;
  final List<DiseasePrediction> topPredictions;
  final List<String> recognizedSymptoms;
  final List<String> ignoredSymptoms;
  final DiseaseInformation? diseaseInformation;
  final bool contentAvailable;
  final bool confidenceThresholdMet;
  final String? warning;
  final String? fallbackMessage;
  final String disclaimer;

  Map<String, dynamic> toRecordFields() {
    final info = diseaseInformation;
    return {
      'ai_category': info?.name.isNotEmpty == true
          ? info!.name
          : prediction.disease,
      'ai_severity': confidenceThresholdMet
          ? 'Informational'
          : 'Low confidence',
      'ai_confidence': prediction.confidence / 100,
      'ai_method': 'ml_model',
      'ai_keywords': recognizedSymptoms.join(', '),
      'ai_recovery_plan': {
        'home_care': info?.selfCareGuidance ?? const <String>[],
        'precautions': info?.emergencyWarningSigns ?? const <String>[],
        'general_advice': [...?info?.prevention, ...?info?.whenToSeeDoctor],
        'estimated_recovery': '',
        'recommended_specialist':
            info?.recommendedSpecialist ?? const <String>[],
        'prediction_source': 'fastapi_random_forest_firestore',
        'disease_key': info?.diseaseKey ?? '',
        'content_available': contentAvailable,
        'top_predictions': topPredictions.map((item) => item.toJson()).toList(),
        'ignored_symptoms': ignoredSymptoms,
        'disclaimer': disclaimer,
        'decision_support': {
          'explanation':
              'The prediction was based on the recognized symptoms and the returned model ranking. It is educational decision support, not a final diagnosis or prescription.',
          'influencing_information': [
            if (recognizedSymptoms.isNotEmpty)
              'Recognized symptoms: ${recognizedSymptoms.join(', ')}',
            'Top ranked result: ${prediction.disease}',
          ],
          'risk_factors': prediction.confidence < 70
              ? ['The returned confidence is below 70%']
              : ['No additional risk flag was returned by this model response'],
          'missing_information': [
            if (ignoredSymptoms.isNotEmpty)
              'Unrecognized or uncertain text: ${ignoredSymptoms.join(', ')}',
            if (!confidenceThresholdMet)
              'The confidence threshold for educational content was not met',
          ],
          'confidence': prediction.confidence / 100,
          'requires_human_review': true,
          'next_action':
              'Verify the complete record and have authorized healthcare personnel review, modify, accept, or reject this recommendation.',
          'review_status': 'Pending human review',
          'final_human_decision': '',
          'human_review_note': '',
        },
      },
    };
  }
}

class DiseasePrediction {
  const DiseasePrediction({
    required this.disease,
    required this.confidence,
    required this.rank,
  });

  factory DiseasePrediction.fromJson(Map<String, dynamic> json) {
    final disease = json['disease']?.toString().trim() ?? '';
    if (disease.isEmpty) throw const FormatException('Missing disease.');
    return DiseasePrediction(
      disease: disease,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
    );
  }

  final String disease;
  final double confidence;
  final int rank;

  Map<String, dynamic> toJson() => {
    'disease': disease,
    'confidence': confidence,
    'rank': rank,
  };
}

class DiseaseInformation {
  const DiseaseInformation({
    required this.diseaseKey,
    required this.name,
    required this.description,
    required this.selfCareGuidance,
    required this.prevention,
    required this.whenToSeeDoctor,
    required this.emergencyWarningSigns,
    required this.recommendedSpecialist,
  });

  factory DiseaseInformation.fromJson(Map<String, dynamic> json) {
    return DiseaseInformation(
      diseaseKey: json['diseaseKey']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      selfCareGuidance: _strings(json['selfCareGuidance']),
      prevention: _strings(json['prevention']),
      whenToSeeDoctor: _strings(json['whenToSeeDoctor']),
      emergencyWarningSigns: _strings(json['emergencyWarningSigns']),
      recommendedSpecialist: _strings(json['recommendedSpecialist']),
    );
  }

  final String diseaseKey;
  final String name;
  final String description;
  final List<String> selfCareGuidance;
  final List<String> prevention;
  final List<String> whenToSeeDoctor;
  final List<String> emergencyWarningSigns;
  final List<String> recommendedSpecialist;
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value.map(_map).whereType<Map<String, dynamic>>().toList();
}

List<String> _strings(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
