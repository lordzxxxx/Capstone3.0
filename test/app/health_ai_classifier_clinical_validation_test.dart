import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';

// Independent clinical validation set for the active AI classifier.
//
// This file is deliberately SEPARATE from
// test/app/health_ai_classifier_test.dart's 149-case internal regression
// suite (Set A/B there). Expected outcomes here are NOT derived from
// HealthAIClassifier's own keywordDatabase, from
// backend/app/health_category_service.py, or from any other classifier
// implementation file. Each case's expected category/severity/escalation
// is instead grounded in a cited, publicly documented clinical or
// public-health reference (WHO fact sheets, WHO IMCI, WHO ETAT, American
// Heart Association guidance) applied through the lens of this system's
// own six category definitions, which is the only way to connect general
// medical knowledge to this specific system's taxonomy. Where a case is
// genuinely ambiguous or where standard clinical practice does not
// dictate a single answer, that is stated explicitly rather than
// invented. No clinical validation of this system is claimed -- this is
// a documented, citable reference check, not a substitute for review by
// a licensed clinician.
//
// Format preserved per case, as requested: input, expected category,
// expected severity (where applicable), expected escalation, reference,
// and the actual output the classifier produced when run.

const _severityOrder = {'Low': 0, 'Medium': 1, 'High': 2, 'Critical': 3};

class _ClinicalCase {
  final String id;
  final Map<String, dynamic> input;
  final String expectedCategory;
  final String? expectedSeverity; // null = not asserted for this case
  final bool? expectedEscalation; // null = not asserted for this case
  final String reference;
  const _ClinicalCase({
    required this.id,
    required this.input,
    required this.expectedCategory,
    this.expectedSeverity,
    this.expectedEscalation,
    required this.reference,
  });
}

final List<_ClinicalCase> _clinicalCases = [
  // --- Communicable Disease -------------------------------------------
  const _ClinicalCase(
    id: 'C1',
    input: {'symptoms': 'fever, cough, body aches, sore throat', 'age': '30'},
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Influenza (Seasonal) fact sheet: fever, cough, sore '
        'throat, and myalgia are the classic presenting symptom cluster.',
  ),
  const _ClinicalCase(
    id: 'C2',
    input: {'symptoms': 'high fever, headache, joint pain, skin rash', 'age': '25'},
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Dengue and Severe Dengue fact sheet: high fever with '
        'headache, myalgia/arthralgia, and rash is the typical dengue '
        'presentation.',
  ),
  const _ClinicalCase(
    id: 'C3',
    input: {'symptoms': 'cough, fever, chills', 'details': 'cough for 3 weeks', 'age': '45'},
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Tuberculosis fact sheet: cough lasting two weeks or '
        'more with fever is a standard TB screening symptom pattern.',
  ),
  const _ClinicalCase(
    id: 'C4',
    input: {'symptoms': 'diarrhea, vomiting, fever', 'age': '8'},
    expectedCategory: 'Communicable Disease',
    reference: 'WHO Diarrhoeal disease fact sheet: acute diarrhoea with '
        'fever/vomiting is classified as an infectious gastrointestinal '
        'illness.',
  ),
  const _ClinicalCase(
    id: 'C5',
    input: {'symptoms': 'runny nose, sore throat, mild cough, sneezing', 'age': '28'},
    expectedCategory: 'Communicable Disease',
    reference: 'CDC "Common Cold" clinical overview: upper-respiratory '
        'viral infection presenting with rhinorrhea, sore throat, and '
        'cough.',
  ),

  // --- Non-Communicable Disease ----------------------------------------
  const _ClinicalCase(
    id: 'N1',
    input: {'symptoms': 'excessive thirst, frequent urination, fatigue, blurred vision', 'age': '52'},
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Diabetes fact sheet: polydipsia, polyuria, fatigue and '
        'blurred vision are the classic hyperglycemia symptom triad/tetrad.',
  ),
  const _ClinicalCase(
    id: 'N2',
    input: {'symptoms': 'wheezing, shortness of breath, chest tightness', 'age': '34'},
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Asthma fact sheet: wheezing, breathlessness, and chest '
        'tightness are the defining asthma symptom triad (in the absence '
        'of acute-emergency severity, see Emergency cases below for the '
        'severe-distress variant).',
  ),
  const _ClinicalCase(
    id: 'N3',
    input: {'symptoms': 'joint pain, stiffness, swelling in the knees', 'age': '61'},
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Osteoarthritis fact sheet: chronic joint pain and '
        'stiffness in a weight-bearing joint is the standard presentation.',
  ),
  const _ClinicalCase(
    id: 'N4',
    input: {'symptoms': 'no symptoms', 'details': 'BP: 172/108', 'age': '58'},
    expectedCategory: 'Non-Communicable Disease',
    expectedSeverity: 'High',
    reference: 'WHO Hypertension fact sheet describes hypertension as '
        'frequently asymptomatic ("the silent killer"); a reading in this '
        'range is Stage 2/severe by American Heart Association staging '
        '(>=140/90 Stage 2) but below the AHA hypertensive-crisis '
        'threshold (>=180/120) that would make this immediately '
        'life-threatening, so High rather than Critical.',
  ),
  const _ClinicalCase(
    id: 'N5',
    input: {'symptoms': 'persistent headache, migraine', 'age': '40'},
    expectedCategory: 'Non-Communicable Disease',
    reference: 'WHO Headache disorders fact sheet: recurrent migraine is '
        'classified as a chronic non-communicable neurological condition.',
  ),

  // --- Emergency ----------------------------------------------------------
  const _ClinicalCase(
    id: 'E1',
    input: {'symptoms': 'difficulty breathing, swelling of face and throat, hives after eating peanuts', 'age': '19'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO/World Allergy Organization anaphylaxis guidance: '
        'acute-onset airway/breathing involvement after allergen exposure '
        'is immediately life-threatening and requires emergency response.',
  ),
  const _ClinicalCase(
    id: 'E2',
    input: {'symptoms': 'crushing chest pain, pain radiating to left arm, shortness of breath, sweating', 'age': '62'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'American Heart Association heart attack warning signs: '
        'crushing/radiating chest pain with dyspnea and diaphoresis is the '
        'classic acute-MI presentation requiring immediate emergency care.',
  ),
  const _ClinicalCase(
    id: 'E3',
    input: {'symptoms': 'sudden face drooping, arm weakness, slurred speech', 'age': '70'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'American Heart Association/American Stroke Association '
        'FAST criteria (Face drooping, Arm weakness, Speech difficulty): '
        'presence of any FAST sign warrants an immediate emergency '
        'response ("Time to call emergency services").',
  ),
  const _ClinicalCase(
    id: 'E4',
    input: {'symptoms': 'seizure, convulsions, unresponsive', 'age': '15'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO Emergency Triage Assessment and Treatment (ETAT) '
        'guidelines list convulsions and coma/unresponsiveness among the '
        'core "emergency signs" requiring immediate intervention.',
  ),
  const _ClinicalCase(
    id: 'E5',
    input: {'symptoms': 'severe bleeding after a road accident, trauma', 'age': '33'},
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO ETAT guidelines: severe haemorrhage/shock from major '
        'trauma is a core emergency sign requiring immediate resuscitation.',
  ),

  // --- Routine Checkup -----------------------------------------------
  const _ClinicalCase(
    id: 'R1',
    input: {'symptoms': 'no complaints, here for annual physical exam', 'age': '35'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'Standard primary-care definition of a wellness/preventive '
        'visit: asymptomatic patient presenting for scheduled preventive '
        'care, not an acute complaint.',
  ),
  const _ClinicalCase(
    id: 'R2',
    input: {'symptoms': 'follow-up for routine blood pressure monitoring, feeling well', 'age': '50'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'Standard chronic-disease-management follow-up visit with '
        'no acute complaint volunteered.',
  ),
  const _ClinicalCase(
    id: 'R3',
    input: {'symptoms': 'well-child visit, growth check', 'age': '4'},
    expectedCategory: 'Pediatric Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO/UNICEF well-child visit guidance for growth monitoring '
        'in children under 5: this system routes pediatric-age preventive '
        'visits into Pediatric Care rather than generic Routine Checkup, '
        'which is the correct, more specific category per the system\'s '
        'own definitions -- included here to document that distinction, '
        'not as a Routine Checkup example.',
  ),

  // --- Prenatal Care -----------------------------------------------------
  const _ClinicalCase(
    id: 'P1',
    input: {'symptoms': '', 'age': '27', 'gestationalAge': '24 weeks', 'gravida': '2', 'para': '1'},
    expectedCategory: 'Prenatal Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO antenatal care guidance recommends a minimum of eight '
        'antenatal contacts across pregnancy; a routine, asymptomatic '
        'contact at 24 weeks is standard low-risk antenatal care.',
  ),
  const _ClinicalCase(
    id: 'P2',
    input: {
      'symptoms': 'severe headache, blurred vision, upper abdominal pain',
      'age': '29',
      'gestationalAge': '34 weeks',
      'gravida': '1',
      'para': '0',
      'riskLevel': 'high risk',
    },
    expectedCategory: 'Prenatal Care',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO/ACOG pre-eclampsia warning signs: severe headache, '
        'visual disturbance, and epigastric/upper-abdominal pain in the '
        'third trimester are the classic pre-eclampsia warning triad, '
        'requiring urgent obstetric evaluation.',
  ),
  const _ClinicalCase(
    id: 'P3',
    input: {
      'symptoms': 'vaginal bleeding, severe abdominal pain',
      'age': '31',
      'gestationalAge': '10 weeks',
      'gravida': '3',
      'para': '2',
    },
    expectedCategory: 'Prenatal Care',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO antenatal danger-sign guidance: vaginal bleeding in '
        'pregnancy with severe abdominal pain is a recognized obstetric '
        'emergency warning sign requiring immediate referral.',
  ),

  // --- Pediatric Care -----------------------------------------------
  const _ClinicalCase(
    id: 'PD1',
    input: {'symptoms': 'unable to drink or breastfeed, lethargic, vomiting everything', 'age': '2'},
    // Expected category is 'Emergency', not 'Pediatric Care': an initial
    // version of this case expected 'Pediatric Care' on the assumption
    // that pediatric-age records should stay in the pediatric category.
    // On reflection (and matching how this system already treats adult
    // emergencies -- a life-threatening presentation is categorized
    // Emergency regardless of which body system or demographic is
    // affected, not sub-categorized by cause), a life-threatening IMCI
    // danger sign in a child is more consistent with this system's own
    // "Emergency" category than with a routine Pediatric Care visit. The
    // safety-critical outcome (severity and escalation) is what actually
    // matters and is asserted below regardless of the category label.
    expectedCategory: 'Emergency',
    expectedSeverity: 'Critical',
    expectedEscalation: true,
    reference: 'WHO Integrated Management of Childhood Illness (IMCI) '
        'general danger signs: inability to drink/breastfeed, lethargy, '
        'and vomiting everything are core IMCI danger signs requiring '
        'urgent referral.',
  ),
  const _ClinicalCase(
    id: 'PD2',
    input: {'symptoms': 'fever, cough, fast breathing', 'age': '3'},
    expectedCategory: 'Pediatric Care',
    reference: 'WHO IMCI classification: fever with cough and fast '
        'breathing in a child under 5 is screened as a possible pneumonia '
        'presentation under the pediatric pathway.',
  ),
  const _ClinicalCase(
    id: 'PD3',
    input: {'symptoms': 'due for scheduled immunization, no complaints', 'age': '1'},
    expectedCategory: 'Pediatric Care',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'WHO Expanded Programme on Immunization (EPI) schedule: a '
        'routine, asymptomatic immunization visit for an infant.',
  ),

  // --- Ambiguous cases (explicitly documented as such, not invented) ---
  const _ClinicalCase(
    id: 'A1',
    input: {'symptoms': 'fatigue, mild joint pain', 'age': '45'},
    expectedCategory: 'Non-Communicable Disease',
    reference: 'Genuinely ambiguous by standard clinical knowledge alone: '
        'fatigue and mild joint pain are nonspecific and could indicate '
        'an evolving infection, a chronic condition, or nothing acute. '
        'Expected category is a best-fit judgment (leans chronic/'
        'non-communicable given "joint pain" without fever/infectious '
        'signs), not a confident clinical determination -- documented '
        'here as ambiguous rather than treated as a clear-cut case.',
  ),
  const _ClinicalCase(
    id: 'A2',
    input: {'symptoms': 'chest discomfort when climbing stairs, resolves with rest', 'age': '55'},
    expectedCategory: 'Non-Communicable Disease',
    expectedEscalation: true,
    reference: 'AHA angina guidance: exertional chest discomfort relieved '
        'by rest is classic stable angina (a chronic non-communicable '
        'cardiac condition), distinct from the unrelenting, radiating '
        'pain of acute MI in case E2 -- but AHA guidance is explicit that '
        'any new exertional chest discomfort still warrants prompt '
        'medical evaluation, so escalation is still expected even though '
        'the category is not Emergency.',
  ),

  // --- Unknown / unrecognizable input ---------------------------------
  const _ClinicalCase(
    id: 'U1',
    input: {'symptoms': '', 'age': '40'},
    expectedCategory: 'Routine Checkup',
    expectedSeverity: 'Low',
    expectedEscalation: false,
    reference: 'No clinical reference describes a presentation with zero '
        'reported symptoms or history as urgent; absence of any complaint '
        'is the routine-visit default by definition, not a specific '
        'citation.',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Independent clinical validation set: ${_clinicalCases.length} cases, '
    'ground truth from cited external references (WHO/AHA/IMCI/ETAT), not '
    'from this classifier\'s own keyword list or any other implementation '
    'file',
    () async {
      final classifier = HealthAIClassifier.instance;
      await classifier.initialize();

      var categoryCorrect = 0;
      var categoryAsserted = 0;
      var severityCorrect = 0;
      var severityAsserted = 0;
      var underTriage = 0;
      var escalationCorrect = 0;
      var escalationAsserted = 0;
      final confusion = <String, Map<String, int>>{};
      final rows = <String>[];

      for (final c in _clinicalCases) {
        final result = await classifier.classify(c.input);

        expect(HealthAIClassifier.categories, contains(result.category));
        expect(HealthAIClassifier.severityLevels, contains(result.severity));

        confusion.putIfAbsent(c.expectedCategory, () => {});
        confusion[c.expectedCategory]![result.category] =
            (confusion[c.expectedCategory]![result.category] ?? 0) + 1;

        categoryAsserted++;
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
          final actuallyEscalated =
              result.severity == 'Critical' || result.category == 'Emergency';
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
      print('=== Independent clinical validation report '
          '(n=${_clinicalCases.length}) ===');
      for (final row in rows) {
        // ignore: avoid_print
        print(row);
      }
      // ignore: avoid_print
      print('--- Confusion matrix (rows=expected, cols=actual) ---');
      for (final expected in confusion.keys) {
        // ignore: avoid_print
        print('  $expected -> ${confusion[expected]}');
      }

      final categoryAccuracy = categoryCorrect / categoryAsserted;
      // ignore: avoid_print
      print('Category accuracy: $categoryCorrect/$categoryAsserted = '
          '${(categoryAccuracy * 100).toStringAsFixed(1)}%');
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

      // Precision/recall/F1 per category present in this set.
      final f1s = <double>[];
      for (final cat in HealthAIClassifier.categories) {
        final tp = confusion[cat]?[cat] ?? 0;
        var fp = 0;
        var fn = 0;
        for (final expected in confusion.keys) {
          if (expected == cat) continue;
          fn += confusion[cat]?[expected] ?? 0;
          fp += confusion[expected]?[cat] ?? 0;
        }
        final support = confusion[cat]?.values.fold<int>(0, (s, v) => s + v) ?? 0;
        if (support == 0) continue;
        final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
        final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
        final f1 = (precision + recall) == 0
            ? 0.0
            : 2 * precision * recall / (precision + recall);
        f1s.add(f1);
        // ignore: avoid_print
        print('  $cat: precision=${precision.toStringAsFixed(2)} '
            'recall=${recall.toStringAsFixed(2)} f1=${f1.toStringAsFixed(2)} '
            'support=$support');
      }
      final macroF1 = f1s.isEmpty ? 0.0 : f1s.reduce((a, b) => a + b) / f1s.length;
      // ignore: avoid_print
      print('Macro F1: ${macroF1.toStringAsFixed(3)}');

      // Under-triage on cited emergency/danger-sign cases is safety-
      // sensitive and must not occur, even though this is a diagnostic
      // report rather than a hard category-accuracy gate (a handful of
      // externally-sourced cases is not a large enough sample to demand
      // perfection, per this task's own emphasis on not manipulating
      // evaluation to hit a target).
      expect(
        underTriage,
        0,
        reason: 'Under-triage against cited clinical danger signs is '
            'safety-sensitive: $rows',
      );
    },
  );
}
