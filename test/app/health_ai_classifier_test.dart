import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';

// Coverage for the active, user-facing AI classifier (Model 2: on-device
// category/severity classifier + rule-based fallback). This is the AI
// system the app actually uses today; the 100-disease Random Forest in
// backend/models/disease_model.pkl is a separate, offline-only artifact
// (/predict stays disabled) and is not exercised by this file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validCategories = HealthAIClassifier.categories;
  const validSeverities = HealthAIClassifier.severityLevels;

  // No AI guidance text may ever recommend a specific medication, dosage,
  // or prescription. Doctors remain solely responsible for those decisions
  // (see AI_ALGORITHM_QA.md). This must hold for every guidance list,
  // regardless of whether the ML model or the rule-based path produced it.
  void expectNoMedicationWording(ClassificationResult result) {
    final forbidden = RegExp(
      r'\b(medications?|medicines?|dosage|prescription|prescribed|antibiotics?|inhaler)\b',
      caseSensitive: false,
    );
    final plan = result.recoveryPlan;
    if (plan == null) return;
    for (final field in ['home_care', 'precautions', 'general_advice']) {
      final items = (plan[field] as List?)?.cast<String>() ?? const [];
      for (final item in items) {
        expect(
          forbidden.hasMatch(item),
          isFalse,
          reason: 'AI guidance must never contain medication wording: "$item"',
        );
      }
    }
  }

  void expectStructurallyValid(ClassificationResult result) {
    expect(validCategories, contains(result.category));
    expect(validSeverities, contains(result.severity));
    expect(result.confidence, inInclusiveRange(0.0, 1.0));
    expectNoMedicationWording(result);
  }

  group('HealthAIClassifier.classify structural safety', () {
    test('every representative record produces a structurally valid, '
        'medication-free result', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final records = <Map<String, dynamic>>[
        {
          'symptoms': 'fever, cough, sore throat, chills',
          'details': 'Temp: 38.5',
          'age': '30',
        },
        {
          'symptoms': 'chronic joint pain, high blood pressure',
          'details': 'BP: 150/95',
          'age': '55',
        },
        {
          'symptoms': 'chest pain, difficulty breathing',
          'details': 'BP: 210/130, Temp: 40.5, HR: 135',
          'age': '60',
        },
        {'symptoms': 'fever, cough', 'details': '', 'age': '5'},
        {'symptoms': '', 'details': '', 'age': '40'},
      ];

      for (final record in records) {
        final result = await classifier.classify(record);
        expectStructurallyValid(result);
      }
    });
  });

  group('Structured prenatal fields route to the rule-based path', () {
    // Regression test for a verified bug: the portable ML model's fixed
    // input vector (age + keyword-hash buckets + 4 vitals; see
    // _preprocessData in health_ai_classifier.dart) has no feature slot for
    // gravida/para/gestationalAge/riskLevel. Before this fix, a high-risk
    // prenatal record with preeclampsia-pattern symptoms ("severe headache,
    // vision changes") but no literal "pregnant"/"prenatal" keyword text
    // was classified as "Communicable Disease" at Medium severity by the ML
    // path, silently dropping the risk signal. classify() now defers to the
    // rule-based path (which reads these fields explicitly) whenever any of
    // them are present.
    test('high-risk prenatal record is classified as Prenatal Care with '
        'escalated severity, not miscategorized by the ML model', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'severe headache, vision changes',
        'details': '',
        'age': '28',
        'gravida': '2',
        'para': '1',
        'gestationalAge': '32 weeks',
        'riskLevel': 'high risk',
        'previousComplications': 'preeclampsia',
      });

      expect(result.category, 'Prenatal Care');
      expect(result.severity, anyOf('High', 'Critical'));
      expect(result.method, 'rule_based');
      expectStructurallyValid(result);
    });

    test('a record with no structured prenatal fields is unaffected by the '
        'prenatal routing rule', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'fever, cough, sore throat, chills',
        'details': 'Temp: 38.5',
        'age': '30',
      });

      // No structured prenatal fields were provided, so the routing rule
      // must not force this into the rule-based path or Prenatal Care.
      expect(result.category, isNot('Prenatal Care'));
      expectStructurallyValid(result);
    });
  });

  group('Emergency vitals always produce an urgent recommended action', () {
    test('critical vitals (hypertensive crisis + hyperthermia + '
        'tachycardia) trigger an immediate-attention action regardless of '
        'the winning category label', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'chest pain, difficulty breathing',
        'details': 'BP: 210/130, Temp: 40.5, HR: 135',
        'age': '60',
      });

      expect(
        result.recommendedActions.any(
          (a) => a.toLowerCase().contains('immediate medical attention'),
        ),
        isTrue,
        reason:
            'Critical-severity vitals must always surface an urgent action, '
            'even if the winning category is not literally "Emergency": '
            'actions=${result.recommendedActions}',
      );
      expectStructurallyValid(result);
    });
  });
}
