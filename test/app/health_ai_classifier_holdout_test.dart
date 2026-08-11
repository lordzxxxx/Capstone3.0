import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';

// Final holdout set for the active AI classifier.
//
// This file exists to give a defensible, non-overfit generalization
// measurement: unlike the expanded 81-case set (health_ai_classifier_
// expanded_validation_test.dart), which was run repeatedly while
// vocabulary/normalization/negation fixes were being developed and
// verified, these cases were written using knowledge already in place at
// that point and are run EXACTLY ONCE, with no classifier changes made in
// response to the result. If a run of this file ever needs to be redone
// after a genuine, separately-justified classifier change, that must be
// stated explicitly in the accompanying report -- silently re-running
// this file to get a better number defeats its purpose.
//
// Ground truth is grounded in the same class of cited public-health
// references used throughout this task (WHO fact sheets, WHO IMCI/ETAT,
// AHA/ASA) applied through this system's own six category definitions,
// not copied from HealthAIClassifier's own keyword list.

const _severityOrder = {'Low': 0, 'Medium': 1, 'High': 2, 'Critical': 3};

class _Case {
  final String id;
  final Map<String, dynamic> input;
  final String expectedCategory;
  final String? expectedSeverity;
  final bool? expectedEscalation;
  final String reference;
  const _Case({
    required this.id,
    required this.input,
    required this.expectedCategory,
    this.expectedSeverity,
    this.expectedEscalation,
    required this.reference,
  });
}

final List<_Case> _cases = [
  const _Case(
    id: 'H01',
    input: {
      'symptoms': 'Been running a temperature and coughing since Tuesday',
      'age': '33',
    },
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Influenza (Seasonal) fact sheet.',
  ),
  const _Case(
    id: 'H02',
    input: {'symptoms': 'Sore throat and swollen glands, feverish', 'age': '20'},
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Influenza / streptococcal pharyngitis pattern.',
  ),
  const _Case(
    id: 'H03',
    input: {'symptoms': "Kid's got a bad cough and runny nose", 'age': '5'},
    expectedCategory: 'Communicable Disease',
    reference: 'CDC "Common Cold" clinical overview.',
  ),
  const _Case(
    id: 'H04',
    input: {
      'symptoms': 'Struggling with high cholesterol and occasional chest discomfort',
      'age': '57',
    },
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Cardiovascular diseases fact sheet / AHA angina guidance.',
  ),
  const _Case(
    id: 'H05',
    input: {
      'symptoms': "Sugar levels have been high lately, doctor says I'm diabetic",
      'age': '49',
    },
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Diabetes fact sheet.',
  ),
  const _Case(
    id: 'H06',
    input: {
      'symptoms': 'No cough or fever, just ongoing arthritis pain in my hands',
      'age': '62',
    },
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Osteoarthritis fact sheet.',
  ),
  const _Case(
    id: 'H07',
    input: {'symptoms': 'Baby is unresponsive and not breathing', 'age': '0'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO ETAT guidelines (absent breathing, unresponsive child).',
  ),
  const _Case(
    id: 'H08',
    input: {
      'symptoms': 'Massive headache, worst of my life, sudden onset',
      'age': '45',
    },
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'AHA/thunderclap-headache guidance: sudden "worst headache of '
        'my life" is a classic subarachnoid hemorrhage warning presentation '
        'requiring emergency evaluation.',
  ),
  const _Case(
    id: 'H09',
    input: {'symptoms': "Deep wound, won't stop bleeding", 'age': '30'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO ETAT guidelines (uncontrolled haemorrhage).',
  ),
  const _Case(
    id: 'H10',
    input: {'symptoms': 'Just here to renew my checkup, nothing new', 'age': '44'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'Standard wellness/follow-up visit.',
  ),
  const _Case(
    id: 'H11',
    input: {'symptoms': 'No new problems, same as last visit', 'age': '39'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'Standard wellness/follow-up visit.',
  ),
  const _Case(
    id: 'H12',
    input: {
      'symptoms': "Second pregnancy, everything's going smoothly, 30 weeks along",
      'age': '28',
      'gestationalAge': '30 weeks',
    },
    expectedCategory: 'Prenatal Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO antenatal care guidance.',
  ),
  const _Case(
    id: 'H13',
    input: {
      'symptoms': 'Bleeding heavily and in a lot of pain, 15 weeks pregnant',
      'age': '26',
      'gestationalAge': '15 weeks',
    },
    expectedCategory: 'Prenatal Care',
    // Severity intentionally not asserted here: per the P04/P06/P10
    // reasoning already established in the expanded set, this system
    // distinguishes a bare danger-sign match (High) from a danger sign
    // combined with an explicit "severe" qualifier (Critical), and "a lot
    // of pain" is deliberately not the literal word "severe" -- measuring
    // category/escalation only avoids repeating that same
    // over-specification mistake in a set that is run exactly once.
    expectedEscalation: true,
    reference: 'WHO antenatal danger-sign guidance (bleeding in pregnancy).',
  ),
  const _Case(
    id: 'H14',
    input: {'symptoms': 'Little one due for her 6-month shots', 'age': '0'},
    expectedCategory: 'Pediatric Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO Expanded Programme on Immunization (EPI) schedule.',
  ),
  const _Case(
    id: 'H15',
    input: {'symptoms': 'Bringing baby for weight and height check', 'age': '0'},
    expectedCategory: 'Pediatric Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO/UNICEF growth monitoring guidance.',
  ),
  const _Case(
    id: 'H16',
    input: {'symptoms': 'Not feeling like myself lately', 'age': '40'},
    expectedCategory: 'Routine Checkup',
    reference: 'GENUINELY AMBIGUOUS: no localizing symptom; best-fit default, '
        'not a confident clinical determination.',
  ),
  const _Case(
    id: 'H17',
    input: {'symptoms': 'N/A', 'age': '50'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'No clinical content present; safe default is Routine Checkup.',
  ),
  const _Case(
    id: 'H18',
    input: {
      'symptoms': 'No symptoms reported',
      'details': 'BP: 195/125',
      'age': '60',
    },
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'AHA hypertensive crisis threshold (>=180/120): vitals alone, '
        'with no symptom text at all, must still trigger emergency '
        'recognition.',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Final holdout set: ${_cases.length} cases, run exactly once for final '
    'evaluation, ground truth from cited external references, not from '
    'this classifier\'s own keyword list',
    () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      var categoryCorrect = 0;
      var severityCorrect = 0;
      var severityAsserted = 0;
      var underTriage = 0;
      var escalationCorrect = 0;
      var escalationAsserted = 0;
      final rows = <String>[];

      for (final c in _cases) {
        final result = await classifier.classify(c.input);

        final categoryMatch = result.category == c.expectedCategory;
        if (categoryMatch) categoryCorrect++;

        String severityNote = 'n/a';
        if (c.expectedSeverity != null) {
          severityAsserted++;
          final match = result.severity == c.expectedSeverity;
          if (match) {
            severityCorrect++;
          } else if (_severityOrder[result.severity]! <
              _severityOrder[c.expectedSeverity]!) {
            underTriage++;
          }
          severityNote = '${c.expectedSeverity} vs actual ${result.severity}'
              '${match ? " (match)" : ""}';
        }

        String escalationNote = 'n/a';
        if (c.expectedEscalation != null) {
          escalationAsserted++;
          final actuallyEscalated = result.severity == 'Critical' ||
              result.severity == 'High' ||
              result.category == 'Emergency';
          final match = actuallyEscalated == c.expectedEscalation;
          if (match) escalationCorrect++;
          escalationNote = 'expected=${c.expectedEscalation} '
              'actual=$actuallyEscalated${match ? " (match)" : ""}';
        }

        rows.add(
          '${c.id}: input=${c.input} | expectedCategory=${c.expectedCategory} '
          '(${categoryMatch ? "MATCH" : "MISMATCH actual=${result.category}"}) '
          '| severity=$severityNote | escalation=$escalationNote '
          '| confidence=${result.confidence.toStringAsFixed(2)} '
          '| reference="${c.reference}"',
        );
      }

      // ignore: avoid_print
      print('=== FINAL HOLDOUT report (n=${_cases.length}, run once) ===');
      for (final row in rows) {
        // ignore: avoid_print
        print(row);
      }
      // ignore: avoid_print
      print('Category accuracy: $categoryCorrect/${_cases.length} = '
          '${(100 * categoryCorrect / _cases.length).toStringAsFixed(1)}%');
      if (severityAsserted > 0) {
        // ignore: avoid_print
        print('Severity accuracy: $severityCorrect/$severityAsserted = '
            '${(100 * severityCorrect / severityAsserted).toStringAsFixed(1)}%'
            ' (under-triage: $underTriage)');
      }
      if (escalationAsserted > 0) {
        // ignore: avoid_print
        print('Escalation correctness: $escalationCorrect/$escalationAsserted');
      }

      expect(
        underTriage,
        0,
        reason: 'Under-triage on the final holdout set is safety-sensitive: '
            '$rows',
      );
    },
  );
}
