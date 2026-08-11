import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';

// Coverage for the active, user-facing AI classifier (Model 2: on-device
// category/severity classifier + rule-based fallback). This is the AI
// system the app actually uses today; the 100-disease Random Forest in
// backend/models/disease_model.pkl is a separate, offline-only artifact
// (/predict stays disabled) and is not exercised by this file.
//
// Reference labels used below are never invented: they come from the
// classifier's own `keywordDatabase` (the same taxonomy it was trained
// and rule-scored against) or from structured fields the checkup/prenatal
// workflows already collect. A case built only from
// `keywordDatabase['prenatal']` keywords is labeled "expected Prenatal
// Care" because that is literally what the system's own taxonomy defines
// that keyword list to mean -- not a clinical judgment call made here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validCategories = HealthAIClassifier.categories;
  const validSeverities = HealthAIClassifier.severityLevels;

  // No AI guidance text may ever recommend a specific medication, dosage,
  // or prescription. Doctors remain solely responsible for those decisions
  // (see AI_ALGORITHM_QA.md). This must hold for every guidance list,
  // regardless of whether the ML model or the rule-based path produced it.
  final forbiddenMedicationWording = RegExp(
    r'\b(medications?|medicines?|dosage|prescription|prescribed|antibiotics?|inhaler)\b',
    caseSensitive: false,
  );

  void expectNoMedicationWording(ClassificationResult result) {
    final plan = result.recoveryPlan;
    if (plan == null) return;
    for (final field in ['home_care', 'precautions', 'general_advice']) {
      final items = (plan[field] as List?)?.cast<String>() ?? const [];
      for (final item in items) {
        expect(
          forbiddenMedicationWording.hasMatch(item),
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
    // Regression tests for a verified bug: the portable ML model's fixed
    // input vector (age + keyword-hash buckets + 4 vitals; see
    // _preprocessData in health_ai_classifier.dart) has no feature slot for
    // gravida/para/gestationalAge/riskLevel. Before this fix, a high-risk
    // prenatal record with preeclampsia-pattern symptoms ("severe headache,
    // vision changes") but no literal "pregnant"/"prenatal" keyword text
    // was classified as "Communicable Disease" at Medium severity by the ML
    // path, silently dropping the risk signal. classify() now defers to the
    // rule-based path (which reads these fields explicitly) whenever any of
    // them are present.
    test('high-risk prenatal record (gravida/para/gestationalAge + '
        'high risk level) is classified as Prenatal Care with escalated '
        'severity, not miscategorized by the ML model', () async {
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

    test('a single structured prenatal field alone (gestationalAge only, '
        'no risk keywords, no symptoms) is enough to route to the '
        'rule-based path and land on Prenatal Care', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': '',
        'details': '',
        'age': '24',
        'gestationalAge': '20 weeks',
      });

      expect(result.category, 'Prenatal Care');
      expect(result.method, 'rule_based');
      expectStructurallyValid(result);
    });

    test('moderate-risk prenatal record produces a lower severity than the '
        'high-risk case above, not an automatic Critical', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'mild back pain',
        'details': '',
        'age': '26',
        'gravida': '1',
        'para': '0',
        'gestationalAge': '18 weeks',
        'riskLevel': 'moderate risk',
      });

      expect(result.category, 'Prenatal Care');
      expect(result.method, 'rule_based');
      expect(result.severity, isNot('Critical'));
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

    test('unconscious/seizure emergency keywords also trigger an urgent '
        'action', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'seizure, unconscious, loss of consciousness',
        'details': '',
        'age': '45',
      });

      expect(
        result.recommendedActions.any(
          (a) =>
              a.toLowerCase().contains('immediate medical attention') ||
              a.toLowerCase().contains('urgent'),
        ),
        isTrue,
        reason: 'actions=${result.recommendedActions}',
      );
      expectStructurallyValid(result);
    });
  });

  group('Unambiguous emergency keywords route to the rule-based path', () {
    // Regression tests for a second verified bug, found via the category
    // accuracy report below: on a test set built only from this
    // classifier's own keywordDatabase['emergency'] keywords, the ML model
    // correctly labeled "Emergency" in only 2 of 5 cases. Two concrete
    // failures: "anaphylaxis, severe allergic reaction" and "seizure,
    // convulsion" were both routed to a non-Emergency category at "High"
    // (not "Critical") severity -- which changes the recommended action
    // from "seek immediate care" to "schedule within 24 hours" for a
    // genuinely life-threatening presentation. classify() now defers to
    // the rule-based path (which explicitly counts these keywords and
    // scored all 5 cases correctly) whenever one is present.
    test('anaphylaxis is classified as Emergency at Critical severity, not '
        'downgraded to a 24-hour-follow-up recommendation', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'anaphylaxis, severe allergic reaction',
        'details': '',
        'age': '27',
      });

      expect(result.category, 'Emergency');
      expect(result.severity, 'Critical');
      expect(result.method, 'rule_based');
      expect(
        result.recommendedActions.any(
          (a) => a.toLowerCase().contains('immediate medical attention'),
        ),
        isTrue,
        reason: 'actions=${result.recommendedActions}',
      );
      expectStructurallyValid(result);
    });

    test('seizure/convulsion is classified as Emergency at Critical '
        'severity', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'seizure, convulsion',
        'details': '',
        'age': '44',
      });

      expect(result.category, 'Emergency');
      expect(result.severity, 'Critical');
      expect(result.method, 'rule_based');
      expectStructurallyValid(result);
    });

    test('text without any emergency keyword is unaffected by the routing '
        'rule', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'fever, cough, sore throat, chills',
        'details': 'Temp: 38.5',
        'age': '30',
      });

      expect(result.category, isNot('Emergency'));
      expectStructurallyValid(result);
    });
  });

  group('Reproducibility', () {
    test('the same input classified twice in a row produces an identical '
        'result (deterministic forward pass, no hidden randomness)', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final input = {
        'symptoms': 'fever, cough, sore throat',
        'details': 'Temp: 38.2, HR: 90',
        'age': '34',
      };

      final first = await classifier.classify(Map<String, dynamic>.from(input));
      final second = await classifier.classify(Map<String, dynamic>.from(input));

      expect(second.category, first.category);
      expect(second.severity, first.severity);
      expect(second.confidence, first.confidence);
      expect(second.method, first.method);
      expect(second.keywords, first.keywords);
    });
  });

  group('Ambiguous / unknown symptom input does not crash and stays safe', () {
    test('nonsense/unrecognized free text still returns a structurally '
        'valid, medication-free result', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'asdkjqwoe zxcvpoiu random gibberish text 12345',
        'details': '',
        'age': '35',
      });

      expectStructurallyValid(result);
    });

    test('contradictory signals (communicable + non-communicable + '
        'prenatal keywords together) still resolve to a single valid '
        'category without crashing', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms':
            'fever, cough, diabetes, hypertension, pregnant, prenatal',
        'details': '',
        'age': '30',
      });

      expectStructurallyValid(result);
    });

    test('a completely empty record defaults to a low-signal result rather '
        'than throwing or fabricating an emergency', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify(<String, dynamic>{});

      expectStructurallyValid(result);
      expect(result.severity, isNot('Critical'));
    });
  });

  group('Category classification accuracy (system taxonomy as reference)', () {
    // Each generator below draws only from HealthAIClassifier's own
    // keywordDatabase for that category, using the same age bands the
    // system's own synthetic-training generator assigns per category
    // (train_model/train_health_classifier.py: create_synthetic_training_data).
    // The "expected" category is therefore read directly from the
    // classifier's own reference taxonomy, not invented for this test.
    final cases = <Map<String, dynamic>>[
      // Communicable Disease (age 5-85 band)
      {'symptoms': 'fever, cough, sore throat', 'age': '30', 'expected': 'Communicable Disease'},
      {'symptoms': 'measles, chickenpox, rash', 'age': '22', 'expected': 'Communicable Disease'},
      {'symptoms': 'dengue, chills, body pain', 'age': '40', 'expected': 'Communicable Disease'},
      {'symptoms': 'tuberculosis, cough, viral infection', 'age': '50', 'expected': 'Communicable Disease'},
      {'symptoms': 'typhoid, diarrhea', 'age': '35', 'expected': 'Communicable Disease'},
      // Non-Communicable Disease (age 30-90 band)
      {'symptoms': 'diabetes, hypertension', 'age': '55', 'expected': 'Non-Communicable Disease'},
      {'symptoms': 'asthma, chronic', 'age': '48', 'expected': 'Non-Communicable Disease'},
      {'symptoms': 'arthritis, gout', 'age': '62', 'expected': 'Non-Communicable Disease'},
      {'symptoms': 'migraine, epilepsy', 'age': '39', 'expected': 'Non-Communicable Disease'},
      {'symptoms': 'kidney disease, anemia', 'age': '70', 'expected': 'Non-Communicable Disease'},
      // Emergency (age 20-85 band)
      {'symptoms': 'chest pain, heart attack', 'age': '58', 'expected': 'Emergency'},
      {'symptoms': 'severe bleeding, trauma', 'age': '33', 'expected': 'Emergency'},
      {'symptoms': 'stroke, unresponsive', 'age': '65', 'expected': 'Emergency'},
      {'symptoms': 'anaphylaxis, severe allergic reaction', 'age': '27', 'expected': 'Emergency'},
      {'symptoms': 'seizure, convulsion', 'age': '44', 'expected': 'Emergency'},
      // Prenatal Care (age 18-45 band) -- via free-text keywords only, no
      // structured fields, so this exercises the ML path's own prenatal
      // keyword recognition rather than the field-based routing rule.
      {'symptoms': 'pregnant, prenatal, morning sickness', 'age': '26', 'expected': 'Prenatal Care'},
      {'symptoms': 'antenatal, trimester, contractions', 'age': '31', 'expected': 'Prenatal Care'},
      {'symptoms': 'gestational, fetal movement concern', 'age': '24', 'expected': 'Prenatal Care'},
      // Pediatric Care (age 1-18 band)
      {'symptoms': 'infant, vaccination, growth monitoring', 'age': '2', 'expected': 'Pediatric Care'},
      {'symptoms': 'child, toddler, immunization', 'age': '6', 'expected': 'Pediatric Care'},
      {'symptoms': 'newborn, developmental', 'age': '1', 'expected': 'Pediatric Care'},
      // Routine Checkup (age 1-90 band; no category keywords at all)
      {'symptoms': 'general checkup', 'age': '40', 'expected': 'Routine Checkup'},
      {'symptoms': 'follow-up visit', 'age': '52', 'expected': 'Routine Checkup'},
      {'symptoms': 'routine monitoring', 'age': '29', 'expected': 'Routine Checkup'},
    ];

    test('empirical category accuracy across the taxonomy-derived test set '
        'is measured and reported (not hidden)', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final perCategory = <String, List<bool>>{};
      final failures = <String>[];
      var correctCount = 0;

      for (final testCase in cases) {
        final expected = testCase['expected'] as String;
        final result = await classifier.classify({
          'symptoms': testCase['symptoms'],
          'details': '',
          'age': testCase['age'],
        });
        expectStructurallyValid(result);

        final isCorrect = result.category == expected;
        perCategory.putIfAbsent(expected, () => []).add(isCorrect);
        if (isCorrect) {
          correctCount++;
        } else {
          failures.add(
            'expected=$expected actual=${result.category} '
            'severity=${result.severity} confidence=${result.confidence.toStringAsFixed(2)} '
            'method=${result.method} symptoms="${testCase['symptoms']}" age=${testCase['age']}',
          );
        }
      }

      final overallAccuracy = correctCount / cases.length;
      // ignore: avoid_print
      print('=== Category classification accuracy report ===');
      // ignore: avoid_print
      print('Overall: $correctCount/${cases.length} = '
          '${(overallAccuracy * 100).toStringAsFixed(1)}%');
      for (final entry in perCategory.entries) {
        final correct = entry.value.where((v) => v).length;
        // ignore: avoid_print
        print('  ${entry.key}: $correct/${entry.value.length}');
      }
      if (failures.isNotEmpty) {
        // ignore: avoid_print
        print('--- Failures (documented, not hidden) ---');
        for (final f in failures) {
          // ignore: avoid_print
          print('  $f');
        }
      }

      // This is a diagnostic/reporting test, not a hard accuracy gate: the
      // deployed ML model's known miscalibration (see
      // docs/AI_ACCURACY_GAP_ANALYSIS.md) is a disclosed, pre-existing
      // limitation, not a regression to hide behind a lowered bar. The one
      // safety property enforced here is that every result stays
      // structurally valid and medication-free (checked above), regardless
      // of whether the category itself is right.
    });
  });

  group('Low-confidence results require professional review', () {
    // Derived from the category-accuracy report above, not an arbitrary
    // number: every case below 0.30 confidence in that 24-case test set
    // was misclassified. See the threshold's derivation comment in
    // health_ai_classifier.dart (_lowConfidenceReviewThreshold).
    test('a low-signal record (no recognizable keywords) is flagged as '
        'needing professional review in the guidance actually shown to '
        'the BHW (precautions), not just an internal field', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'asdkjqwoe zxcvpoiu random gibberish text 12345',
        'details': '',
        'age': '35',
      });

      expect(result.confidence, lessThan(0.35));
      final precautions =
          (result.recoveryPlan?['precautions'] as List?)?.cast<String>() ??
          const <String>[];
      expect(
        precautions.any((p) => p.toLowerCase().contains('professional review')),
        isTrue,
        reason: 'precautions=$precautions',
      );
      expect(
        result.recommendedActions.any(
          (a) => a.toLowerCase().contains('professional review'),
        ),
        isTrue,
      );
      expectStructurallyValid(result);
    });

    test('a high-confidence result is not flagged with the low-confidence '
        'advisory', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      final result = await classifier.classify({
        'symptoms': 'measles, chickenpox',
        'details': '',
        'age': '22',
      });

      expect(result.confidence, greaterThanOrEqualTo(0.35));
      final precautions =
          (result.recoveryPlan?['precautions'] as List?)?.cast<String>() ??
          const <String>[];
      expect(
        precautions.any((p) => p.toLowerCase().contains('professional review')),
        isFalse,
        reason: 'precautions=$precautions',
      );
    });
  });

  group('Severity responds to vital-sign severity (monotonicity check)', () {
    test('progressively worse blood pressure/temperature/heart rate do not '
        'produce a *lower* severity than a normal-vitals baseline', () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      const order = {'Low': 0, 'Medium': 1, 'High': 2, 'Critical': 3};

      final normal = await classifier.classify({
        'symptoms': 'mild fatigue',
        'details': 'BP: 118/76, Temp: 36.8, HR: 78',
        'age': '40',
      });
      final severe = await classifier.classify({
        'symptoms': 'mild fatigue',
        'details': 'BP: 200/125, Temp: 40.2, HR: 140',
        'age': '40',
      });

      expectStructurallyValid(normal);
      expectStructurallyValid(severe);
      expect(
        order[severe.severity]!,
        greaterThanOrEqualTo(order[normal.severity]!),
        reason: 'normal=${normal.severity} (${normal.method}), '
            'severe=${severe.severity} (${severe.method}) -- severe vitals '
            'must not be rated as less urgent than normal vitals',
      );
    });
  });
}
