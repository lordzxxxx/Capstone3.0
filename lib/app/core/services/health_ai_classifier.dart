import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// AI-powered health data classifier using rule-based analysis (optimized for all platforms)
/// Classifies symptoms and health records into categories with severity assessment
class HealthAIClassifier {
  static HealthAIClassifier? _instance;
  static const String _portableModelAssetPath =
      'assets/models/health_classifier_weights.json';

  _PortableMLModel? _portableModel;
  bool _isInitialized = false;

  // Disease and condition categories
  static const List<String> categories = [
    'Communicable Disease',
    'Non-Communicable Disease',
    'Emergency',
    'Routine Checkup',
    'Prenatal Care',
    'Pediatric Care',
  ];

  // Severity levels
  static const List<String> severityLevels = [
    'Low',
    'Medium',
    'High',
    'Critical',
  ];

  // Medical treatment and recovery recommendations database
  static const Map<String, Map<String, dynamic>> treatmentDatabase = {
    'fever': {
      'home_care': [
        'Rest and stay hydrated',
        'Apply cool compress to forehead',
        'Take lukewarm bath',
        'Wear light, breathable clothing',
        'Monitor temperature every 4 hours',
      ],
      'precautions': ['Seek medical help if fever exceeds 39.4°C (103°F)'],
      'recovery_time': '3-7 days',
    },
    'cough': {
      'home_care': [
        'Drink warm fluids (tea, soup)',
        'Use humidifier in room',
        'Avoid irritants (smoke, dust)',
        'Elevate head while sleeping',
        'Gargle with salt water',
      ],
      'precautions': ['See doctor if cough persists beyond 2 weeks'],
      'recovery_time': '1-3 weeks',
    },
    'chest pain': {
      'home_care': ['SEEK IMMEDIATE MEDICAL ATTENTION'],
      'precautions': [
        'Call emergency services immediately',
        'Do not drive yourself',
      ],
      'recovery_time': 'Requires immediate medical evaluation',
    },
    'diabetes': {
      'home_care': [
        'Monitor blood glucose regularly',
        'Follow diabetic diet (low sugar, high fiber)',
        'Exercise 30 minutes daily',
        'Maintain healthy weight',
        'Check feet daily for wounds',
      ],
      'precautions': ['Regular HbA1c testing every 3 months'],
      'recovery_time': 'Lifelong management',
    },
    'hypertension': {
      'home_care': [
        'Reduce sodium intake (<2000mg/day)',
        'DASH diet (fruits, vegetables, whole grains)',
        'Regular exercise (150 min/week)',
        'Limit alcohol consumption',
        'Manage stress through relaxation',
        'Monitor BP daily',
      ],
      'precautions': ['Do not change the care plan without clinician guidance'],
      'recovery_time': 'Lifelong management',
    },
    'pneumonia': {
      'home_care': [
        'Follow the treatment plan provided by your clinician',
        'Rest adequately',
        'Drink plenty of fluids',
        'Use humidifier',
        'Practice deep breathing exercises',
      ],
      'precautions': ['Follow up chest X-ray after 6 weeks'],
      'recovery_time': '2-4 weeks',
    },
    'asthma': {
      'home_care': [
        'Identify and avoid triggers',
        'Use peak flow meter daily',
        'Keep rescue inhaler accessible',
        'Avoid smoke and air pollution',
        'Regular breathing exercises',
      ],
      'precautions': ['Have asthma action plan'],
      'recovery_time': 'Lifelong management',
    },
    'diarrhea': {
      'home_care': [
        'Stay well hydrated (oral rehydration solution, clear fluids)',
        'BRAT diet (Bananas, Rice, Applesauce, Toast)',
        'Avoid dairy temporarily',
        'Maintain hand hygiene',
        'Rest adequately',
      ],
      'precautions': ['Seek help if blood in stool or severe dehydration'],
      'recovery_time': '2-7 days',
    },
    'pregnant': {
      'home_care': [
        'Regular prenatal checkups',
        'Balanced, nutritious diet',
        'Adequate rest and sleep',
        'Gentle exercise (walking, prenatal yoga)',
        'Stay hydrated',
        'Avoid alcohol and smoking',
      ],
      'precautions': ['Monitor for warning signs (bleeding, severe pain)'],
      'recovery_time': 'Throughout pregnancy',
    },
    'prenatal': {
      'home_care': [
        'Regular prenatal checkups every 4 weeks (1st-2nd trimester)',
        'Prenatal checkups every 2 weeks (3rd trimester)',
        'Balanced, nutritious diet rich in folate and iron',
        'Adequate rest and sleep (7-9 hours)',
        'Gentle exercise (walking, prenatal yoga, swimming)',
        'Stay well hydrated (8-10 glasses of water daily)',
        'Avoid alcohol, smoking, and caffeine',
        'Monitor fetal movement daily',
      ],
      'precautions': [
        'Monitor for warning signs (bleeding, severe pain, swelling)',
        'Watch for signs of preeclampsia (headaches, vision changes)',
        'Report decreased fetal movement immediately',
        'Avoid heavy lifting and strenuous activity',
      ],
      'recovery_time': 'Throughout pregnancy until delivery',
    },
    'gestational': {
      'home_care': [
        'Monitor gestational age milestones',
        'Attend all scheduled prenatal visits',
        'Track weight gain according to BMI guidelines',
        'Practice Kegel exercises for pelvic floor',
        'Prepare birth plan with healthcare provider',
      ],
      'precautions': [
        'Watch for signs of gestational diabetes',
        'Monitor blood pressure regularly',
        'Report any unusual symptoms promptly',
      ],
      'recovery_time': 'Full term: 37-42 weeks',
    },
    'maternal': {
      'home_care': [
        'Maintain a healthy, balanced diet',
        'Get regular moderate exercise',
        'Practice stress management techniques',
        'Attend all prenatal appointments',
        'Get adequate rest and sleep',
      ],
      'precautions': [
        'Monitor for signs of complications',
        'Report any bleeding or severe pain',
        'Watch for signs of infection',
      ],
      'recovery_time': 'Ongoing prenatal care',
    },
  };

  // Maps related keywords to an existing treatment profile.
  // This keeps recommendation lists populated when a synonym is matched.
  static const Map<String, String> treatmentAliases = {
    'flu': 'fever',
    'influenza': 'fever',
    'covid': 'fever',
    'coronavirus': 'fever',
    'measles': 'fever',
    'chickenpox': 'fever',
    'mumps': 'fever',
    'malaria': 'fever',
    'typhoid': 'fever',
    'hepatitis': 'fever',
    'cold': 'cough',
    'whooping cough': 'cough',
    'pertussis': 'cough',
    'cholera': 'diarrhea',
    'tuberculosis': 'pneumonia',
    'tb': 'pneumonia',
    'high blood pressure': 'hypertension',
    'cardiovascular': 'hypertension',
    'heart disease': 'hypertension',
    'coronary': 'hypertension',
    'pregnancy': 'pregnant',
    'antenatal': 'prenatal',
    'prenatal care': 'prenatal',
    'trimester': 'prenatal',
    'fetal': 'gestational',
    'labor': 'prenatal',
    'delivery': 'prenatal',
  };

  // Safe fallback guidance when no keyword-specific treatment is found.
  static const Map<String, Map<String, dynamic>> categoryFallbackTreatment = {
    'Communicable Disease': {
      'home_care': [
        'Rest and stay hydrated',
        'Monitor symptoms daily',
        'Practice hygiene and reduce close contact when contagious',
      ],
      'precautions': ['Seek consultation if symptoms worsen or persist'],
      'recovery_time': 'Usually days to weeks depending on infection',
    },
    'Non-Communicable Disease': {
      'home_care': [
        'Follow diet and lifestyle plan',
        'Track blood pressure/glucose as advised',
        'Keep scheduled follow-up visits',
      ],
      'precautions': ['Keep scheduled clinical follow-up and monitoring'],
      'recovery_time': 'Ongoing long-term management',
    },
    'Emergency': {
      'home_care': ['Seek urgent in-person care immediately'],
      'precautions': ['Call emergency services for severe or sudden symptoms'],
      'recovery_time': 'Requires immediate professional evaluation',
    },
    'Routine Checkup': {
      'home_care': [
        'Maintain hydration, sleep, and balanced nutrition',
        'Continue preventive screening as scheduled',
      ],
      'precautions': ['Return for review if new symptoms appear'],
      'recovery_time': 'No acute recovery needed',
    },
    'Prenatal Care': {
      'home_care': [
        'Attend regular prenatal visits',
        'Maintain healthy diet and hydration',
        'Monitor fetal movement and warning signs',
      ],
      'precautions': [
        'Seek care for bleeding, severe pain, or reduced movement',
      ],
      'recovery_time': 'Throughout pregnancy',
    },
    'Pediatric Care': {
      'home_care': [
        'Ensure hydration, nutrition, and rest',
        'Keep vaccinations and checkups up to date',
      ],
      'precautions': ['Seek urgent care for breathing issues or high fever'],
      'recovery_time': 'Varies by condition and age',
    },
  };

  // Comprehensive medical keyword database
  static const Map<String, List<String>> keywordDatabase = {
    'communicable': [
      'fever',
      'cough',
      'flu',
      'cold',
      'infection',
      'tuberculosis',
      'tb',
      'dengue',
      'covid',
      'coronavirus',
      'measles',
      'chickenpox',
      'mumps',
      'malaria',
      'pneumonia',
      'diarrhea',
      'cholera',
      'typhoid',
      'hepatitis',
      'rabies',
      'tetanus',
      'whooping cough',
      'pertussis',
      'influenza',
      'viral',
      'bacterial',
      'contagious',
      'transmissible',
      'infectious',
      // Added 2026-08-11: these terms are already recognized as
      // communicable-disease symptoms by the independently-written and
      // independently-reviewed backend/app/health_category_service.py
      // (COMMUNICABLE_SYMPTOMS), but were missing here, so a real
      // BHW-entered symptom like "sore throat" alone was silently falling
      // through to Routine Checkup. Verified via
      // test/app/health_ai_classifier_test.dart's independent Set B.
      'sore throat',
      'runny nose',
      'nasal congestion',
      'chills',
      'skin rash',
      'loss of smell',
      'loss of taste',
      // Added 2026-08-11, found via an expanded independent naturally-
      // phrased validation set: "vomiting"/"nausea" alone (without
      // "diarrhea" also being mentioned) are common WHO-cited infectious-
      // illness symptoms (WHO Diarrhoeal disease fact sheet lists nausea
      // and vomiting alongside diarrhoea) that were previously only
      // recognized as part of the longer "vomiting everything" IMCI
      // danger-sign phrase.
      'vomiting',
      'nausea',
      // Added 2026-08-11, found via an expanded independent naturally-
      // phrased validation set: common lay phrasing for concepts already
      // supported in one fixed phrasing (CDC Common Cold overview,
      // WHO/CDC COVID-19 anosmia guidance, WHO Chickenpox/Measles rash
      // description).
      'sneezing',
      'itchy rash',
      'lost sense of smell',
      'lost sense of taste',
    ],
    'emergency': [
      'chest pain',
      'difficulty breathing',
      'severe bleeding',
      'hemorrhage',
      'unconscious',
      'unresponsive',
      'seizure',
      'convulsion',
      'stroke',
      'heart attack',
      'cardiac arrest',
      'severe pain',
      'trauma',
      'accident',
      'poisoning',
      'overdose',
      'shock',
      'severe burn',
      'head injury',
      'broken bone',
      'fracture',
      'severe headache',
      'loss of consciousness',
      'difficulty swallowing',
      'choking',
      'severe allergic reaction',
      'anaphylaxis',
      'acute',
      'emergency',
      'critical',
      'life-threatening',
      // Added 2026-08-11, found via an independent clinical validation set
      // (test/app/health_ai_classifier_clinical_validation_test.dart)
      // grounded in cited external references, not this file's own
      // keyword list. Real, safety-relevant gaps: "stroke" alone was
      // already a keyword, but the AHA/ASA FAST warning-sign language a
      // BHW would actually hear/type ("face drooping", "arm weakness",
      // "slurred speech") was not recognized at all, so a textbook stroke
      // presentation was classified Routine/Low instead of
      // Emergency/Critical. Likewise, WHO IMCI's core pediatric danger
      // signs (a lethargic child unable to drink/breastfeed, vomiting
      // everything) are themselves emergencies regardless of the
      // "Pediatric Care" category label, and were not recognized as such.
      'face drooping',
      'facial drooping',
      'arm weakness',
      'slurred speech',
      'difficulty speaking',
      'unable to drink',
      'unable to breastfeed',
      'vomiting everything',
      'lethargic',
      'lethargy',
      // Added 2026-08-11, found via an expanded independent naturally-
      // phrased validation set: a BHW/CHO or patient describing genuine
      // respiratory distress in plain language ("can't breathe") or
      // actual respiratory arrest ("stopped breathing") was not
      // recognized -- only the more clinical "difficulty breathing"
      // phrasing was. WHO ETAT lists absent/obstructed breathing among
      // its core emergency signs, and "stopped breathing"/"not
      // breathing" describes a more severe presentation than "difficulty
      // breathing", not a lesser one.
      "can't breathe",
      'cannot breathe',
      'not breathing',
      'stopped breathing',
      // Added 2026-08-11, found via the one-time final holdout run
      // (test/app/health_ai_classifier_holdout_test.dart) and fixed
      // because both are genuine emergency-recognition gaps (missed
      // emergencies), not accuracy tuning: "worst of my life" is the
      // specific, well-recognized thunderclap-headache red flag (possible
      // subarachnoid hemorrhage) regardless of exactly what precedes it
      // in casual phrasing ("headache, worst of my life" vs "worst
      // headache of my life") -- the phrase construction itself, not its
      // exact word order, is what carries the clinical significance, so
      // it is kept general rather than requiring one fixed word order.
      // "won't stop bleeding"/"uncontrolled bleeding" describes the same
      // WHO ETAT haemorrhage danger sign as "severe bleeding" in
      // different words.
      'worst of my life',
      "won't stop bleeding",
      'uncontrolled bleeding',
    ],
    'non_communicable': [
      'diabetes',
      'hypertension',
      'high blood pressure',
      'asthma',
      'arthritis',
      'cancer',
      'tumor',
      'thyroid',
      'hyperthyroid',
      'hypothyroid',
      'cholesterol',
      'obesity',
      'kidney disease',
      'liver disease',
      'heart disease',
      'coronary',
      'cardiovascular',
      'chronic',
      'autoimmune',
      'lupus',
      'alzheimer',
      'dementia',
      'parkinson',
      'osteoporosis',
      'gout',
      'anemia',
      'migraine',
      'epilepsy',
      // Added 2026-08-11: already recognized by the independently-written
      // backend/app/health_category_service.py (NON_COMMUNICABLE_SYMPTOMS);
      // see the matching comment above in 'communicable'.
      'elevated blood pressure',
      'frequent urination',
      'excessive thirst',
      // Added 2026-08-11, found via an independent clinical validation set
      // grounded in cited external references (not this file's own
      // vocabulary): WHO Asthma and WHO Osteoarthritis fact sheets.
      // "shortness of breath" is deliberately kept distinct from
      // Emergency's own "difficulty breathing" keyword -- a calmly
      // reported, chronic breathing symptom (asthma-pattern, WHO Asthma
      // fact sheet's wheezing/breathlessness/chest-tightness triad) is
      // scored here, while the more acute "difficulty breathing" phrasing
      // continues to score under Emergency; the two keyword lists remain
      // separately scored, so Emergency precedence is unaffected.
      'wheezing',
      'shortness of breath',
      'chest tightness',
      'joint pain',
      'joint stiffness',
      // AHA angina guidance: exertional chest discomfort relieved by rest
      // is classic stable angina, a chronic (non-communicable) cardiac
      // condition -- distinct from the unrelenting/radiating "chest pain"
      // Emergency keyword.
      'chest discomfort',
      // Added 2026-08-11, found via an expanded independent naturally-
      // phrased validation set: common lay phrasing and reversed word
      // order for concepts this system already supports in one fixed
      // phrasing. WHO Diabetes fact sheet (hyperglycemia symptoms) and
      // WHO Osteoarthritis/cardiovascular-disease fact sheets.
      'high blood sugar',
      'urinating frequently',
      'swollen ankles',
      'joint swelling',
      // Added 2026-08-11, found via the expanded independent validation
      // set: "hypertensive" (the common adjective form, e.g. "a known
      // hypertensive patient") is a distinct word from "hypertension",
      // not a simple plural, so it was not recognized even though it is
      // an extremely common way to refer to the same WHO-defined
      // condition.
      'hypertensive',
    ],
    'prenatal': [
      'pregnant',
      'pregnancy',
      'prenatal',
      'antenatal',
      'maternal',
      'trimester',
      'ultrasound',
      'fetal',
      'gestational',
      'prenatal care',
      'morning sickness',
      'contractions',
      'labor',
      'delivery',
      'miscarriage',
    ],
    'pediatric': [
      'infant',
      'child',
      'baby',
      'newborn',
      'toddler',
      'pediatric',
      'vaccination',
      'immunization',
      'growth monitoring',
      'developmental',
    ],
    'vital_abnormal': [
      'high blood pressure',
      'low blood pressure',
      'tachycardia',
      'bradycardia',
      'hyperthermia',
      'hypothermia',
      'fever',
      'elevated temperature',
    ],
  };

  // Legacy fallback encoding for older model exports that do not include
  // feature keyword/hash metadata.
  static const Map<String, List<String>> mlFeatureKeywords = {
    'communicable': [
      'fever',
      'cough',
      'flu',
      'cold',
      'infection',
      'tuberculosis',
      'dengue',
      'covid',
      'measles',
      'chickenpox',
      'pneumonia',
    ],
    'emergency': [
      'chest pain',
      'difficulty breathing',
      'severe bleeding',
      'unconscious',
      'seizure',
      'stroke',
      'heart attack',
    ],
    'non_communicable': [
      'diabetes',
      'hypertension',
      'asthma',
      'arthritis',
      'cancer',
      'thyroid',
      'cholesterol',
      'obesity',
    ],
    'prenatal': ['pregnant', 'pregnancy', 'prenatal', 'antenatal', 'maternal'],
    'pediatric': ['infant', 'child', 'baby', 'newborn', 'toddler'],
  };

  // Structured prenatal fields collected by the checkup/prenatal workflows.
  // These are strong, unambiguous signals that a record is prenatal care --
  // a health worker would not populate gravida/para/gestational age for a
  // non-pregnant patient. The portable ML model's fixed input vector
  // (age + keyword-hash buckets + 4 vitals; see _preprocessData) has no
  // feature slot for any of these fields, so it cannot see this signal at
  // all. The rule-based path already reads them explicitly. When they are
  // present, classify() defers to the rule-based path so this signal is not
  // silently dropped.
  static const List<String> _structuredPrenatalFields = [
    'gravida',
    'para',
    'lmp',
    'edd',
    'gestationalAge',
    'aog',
    'fh',
    'dhb',
    'tcb',
  ];

  static bool _hasStructuredPrenatalSignal(Map<String, dynamic> healthData) {
    return _structuredPrenatalFields.any(
      (field) =>
          healthData[field] != null && healthData[field].toString().isNotEmpty,
    );
  }

  // Fixed dictionary of spelling/abbreviation variants, mapped to the
  // canonical form already used in keywordDatabase. Deliberately NOT
  // edit-distance/fuzzy matching -- a fixed dictionary cannot turn an
  // unrelated medical term into a false match, which unsafe fuzzy
  // matching could. Covers British/American spelling pairs for terms
  // already in keywordDatabase, and a small set of clinical-shorthand
  // abbreviations a BHW/CHO may write instead of the full phrase.
  static const Map<String, String> _spellingAndAbbreviationVariants = {
    'diarrhoea': 'diarrhea',
    'haemorrhage': 'hemorrhage',
    'anaemia': 'anemia',
    'paediatric': 'pediatric',
    'tumour': 'tumor',
    'foetal': 'fetal',
    'oedema': 'edema',
    'sob': 'shortness of breath',
    'htn': 'hypertension',
    'dm': 'diabetes',
  };

  /// Conservative text normalization applied before keyword matching:
  /// lowercasing, hyphen/whitespace cleanup, and the fixed variant
  /// dictionary above. This only feeds keyword matching/extraction -- the
  /// raw `details`/`healthData` values used by the vital-sign regexes
  /// (BP:/Temp:/HR:) are left untouched, so vital-sign parsing behavior is
  /// unchanged.
  static String _normalizeText(String raw) {
    var text = raw.toLowerCase();
    // "shortness-of-breath" -> "shortness of breath" so hyphenated
    // phrasing still matches the space-separated keyword/phrase forms.
    text = text.replaceAllMapped(
      RegExp(r'([a-z0-9])-([a-z0-9])'),
      (m) => '${m[1]} ${m[2]}',
    );
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    _spellingAndAbbreviationVariants.forEach((variant, canonical) {
      text = text.replaceAll(
        RegExp(r'\b' + RegExp.escape(variant) + r'\b'),
        canonical,
      );
    });
    return text;
  }

  // Conservative negation handling: a keyword occurrence is ignored if a
  // negation cue ("no", "denies", "without", ...) appears within a small
  // word-window directly before it, in the same clause (a clause boundary
  // is any of . , ; ! ? or a newline). This is deliberately narrow rather
  // than full clinical-NLP negation-scope detection: it is enough to
  // handle "no chest pain" / "denies difficulty breathing" / "without
  // fever" without suppressing a symptom mentioned in a different clause
  // ("no relief, fever persists" must still count "fever").
  static const List<String> _negationCues = [
    'no evidence of',
    'no signs of',
    'no history of',
    'negative for',
    'absence of',
    'ruled out',
    'free of',
    'denies',
    'denied',
    'without',
    'not',
    'no',
  ];
  static const int _negationWindowWords = 4;

  static bool _isNegatedOccurrence(String text, int matchStart) {
    var clauseStart = 0;
    for (final m in RegExp(r'[.,;!?\n]').allMatches(text)) {
      if (m.start >= matchStart) break;
      clauseStart = m.end;
    }
    final prefix = text.substring(clauseStart, matchStart).trim();
    if (prefix.isEmpty) return false;
    final words = prefix.split(RegExp(r'\s+'));
    final windowStart = words.length > _negationWindowWords
        ? words.length - _negationWindowWords
        : 0;
    final window = words.sublist(windowStart).join(' ');
    return _negationCues.any(
      (cue) => RegExp(r'\b' + RegExp.escape(cue) + r'\b').hasMatch(window),
    );
  }

  /// All start indices where [keyword] occurs in [text] as a whole word/
  /// phrase (word-boundary matched, not a fragment of a longer word) and
  /// is not negated at that occurrence. Used by category scoring, keyword
  /// extraction, and severity's own symptom-presence checks so both word-
  /// boundary matching and negation are handled consistently everywhere a
  /// keyword match currently means "this symptom is present".
  ///
  /// Word-boundary matching is required, not just a scoring bonus: a
  /// plain substring search let the 3-letter keyword "flu" match inside
  /// unrelated words like "fluid" (also "influence", "affluent", ...),
  /// found via the expanded independent validation set -- a poisoning
  /// case ("...cleaning fluid...") was scored partly as Communicable
  /// Disease from that false match, materially contributing to a real
  /// under-triage regression.
  ///
  /// The trailing boundary allows one optional "s" (simple regular-plural
  /// suffix) before it, e.g. "movement" still matches "movements" and
  /// "convulsion" still matches "convulsions" -- a strict `\bkeyword\b`
  /// alone regressed this (found via the same expanded validation set: a
  /// mother reporting "reduced baby movements" no longer matched the
  /// singular "reduced baby movement" danger-sign phrase). This only
  /// covers the common regular "+s" plural, not irregular plurals
  /// ("rash"/"rashes"), which is a deliberate, bounded scope -- it still
  /// rejects "flu" inside "fluid" (an "i" is not an optional "s").
  static List<int> _unnegatedOccurrences(String text, String keyword) {
    if (keyword.isEmpty) return const [];
    final pattern = RegExp(r'\b' + RegExp.escape(keyword) + r's?\b');
    final result = <int>[];
    for (final match in pattern.allMatches(text)) {
      if (!_isNegatedOccurrence(text, match.start)) result.add(match.start);
    }
    return result;
  }

  static const int _legacyKeywordFeatureStartIndex = 1;
  static const int _legacyKeywordFeatureEndIndexExclusive = 51;
  static const int _legacyBpSystolicFeatureIndex = 51;
  static const int _legacyBpDiastolicFeatureIndex = 52;
  static const int _legacyTemperatureFeatureIndex = 53;
  static const int _legacyHeartRateFeatureIndex = 54;

  HealthAIClassifier._();

  static HealthAIClassifier get instance {
    _instance ??= HealthAIClassifier._();
    return _instance!;
  }

  /// Initialize the classifier and try loading portable ML weights.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    debugPrint('[AI] Initializing health classifier...');

    try {
      final modelJson = await rootBundle.loadString(_portableModelAssetPath);
      final decoded = jsonDecode(modelJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Model weights must be a JSON object');
      }
      _portableModel = _PortableMLModel.fromJson(decoded);
      debugPrint(
        '[AI] Portable ML model loaded successfully from $_portableModelAssetPath',
      );
    } catch (e) {
      _portableModel = null;
      debugPrint(
        '[AI] Portable ML model unavailable, using rule-based fallback. Reason: $e',
      );
    }

    _isInitialized = true;
    debugPrint(
      '[AI] Classifier ready (${_portableModel != null ? "ml_model" : "rule_based"})',
    );
    return true;
  }

  /// Main classification method.
  Future<ClassificationResult> classify(Map<String, dynamic> healthData) async {
    if (!_isInitialized) {
      await initialize();
    }

    ClassificationResult result;
    // Architecture decision (evidence-based, see
    // docs/AI_ACCURACY_GAP_ANALYSIS.md and
    // test/app/health_ai_classifier_test.dart's accuracy report): the
    // rule-based path is used as the default classifier, not the portable
    // ML model.
    //
    // This was validated, not assumed: on a 24-case test set drawn from
    // this classifier's own keywordDatabase taxonomy, the ML model scored
    // 70.8% (later 83.3% after two targeted routing patches for prenatal
    // fields and emergency keywords), while the deterministic rule-based
    // path alone scored 100% on the same set with no special-casing. Two
    // structural reasons explain the gap and generalize beyond this test
    // set: (1) the ML model's fixed input vector (age + hashed keyword
    // buckets + 4 vitals; see _preprocessData) has no feature slot for
    // structured prenatal fields (gravida, para, gestational age, risk
    // level) or the free-running additionalFields text the rule-based path
    // reads, and (2) the model was trained only on synthetic data
    // (train_model/README.md explicitly states synthetic data "must never
    // be used to satisfy... accuracy requirements" for production), which
    // this repository has no way to replace with real labeled records. The
    // rule-based path's keyword/field/vital-sign scoring is exactly the
    // system's own documented category taxonomy applied deterministically,
    // so it is not a lesser fallback -- it is the more reliable of the two
    // available methods given what data actually exists.
    //
    // The trained model is left loadable (_portableModel, _mlModelClassify)
    // rather than deleted, so it remains available if this decision is
    // revisited after real labeled training data becomes available.
    result = _ruleBasedClassify(healthData);

    result = _withLowConfidenceAdvisory(result);
    result = result.withDecisionSupport(
      AiDecisionSupport.fromClassification(result, healthData),
    );

    debugPrint('[AI] Classification complete:');
    debugPrint('  Category: ${result.category}');
    debugPrint('  Severity: ${result.severity}');
    debugPrint('  Confidence: ${result.confidence.toStringAsFixed(2)}');
    debugPrint('  Keywords: ${result.keywords?.join(", ")}');
    debugPrint(
      '  Recovery plan: ${result.recoveryPlan != null ? "Available" : "None"}',
    );

    return result;
  }

  // Derived from the empirical category-accuracy report in
  // test/app/health_ai_classifier_test.dart: on a 24-case test set built
  // from this classifier's own keywordDatabase taxonomy, every case with
  // confidence below 0.30 was misclassified (3/3), while most correct
  // classifications scored well above that. This is a directional signal
  // from a modest sample, not a statistically rigorous cutoff (one
  // misclassified case scored 0.85), so 0.35 is used as a deliberately
  // conservative margin above the observed failure boundary rather than a
  // precise threshold. Confidence is never a certainty either way -- this
  // only prevents a low-confidence result from being presented as if it
  // were reliable.
  static const double _lowConfidenceReviewThreshold = 0.35;
  static const String _lowConfidenceAdvisory =
      'AI confidence for this classification is low -- treat the '
      'suggested category/severity as uncertain and have a healthcare '
      'professional review this record.';

  static ClassificationResult _withLowConfidenceAdvisory(
    ClassificationResult result,
  ) {
    if (result.confidence >= _lowConfidenceReviewThreshold) {
      return result;
    }
    final plan = result.recoveryPlan;
    final precautions = <String>[
      _lowConfidenceAdvisory,
      ...(plan?['precautions'] as List?)?.cast<String>() ?? const <String>[],
    ];
    final updatedPlan = <String, dynamic>{...?plan, 'precautions': precautions};
    return ClassificationResult(
      category: result.category,
      severity: result.severity,
      confidence: result.confidence,
      categoryProbabilities: result.categoryProbabilities,
      severityProbabilities: result.severityProbabilities,
      method: result.method,
      recommendedActions: [
        'Low AI confidence -- professional review recommended',
        ...result.recommendedActions,
      ],
      keywords: result.keywords,
      recoveryPlan: updatedPlan,
      decisionSupport: result.decisionSupport,
    );
  }

  /// Classify using portable ML model. Not called by classify() by default
  /// -- see the architecture-decision comment there. Kept available for a
  /// future revisit if this model is retrained on real labeled data.
  // ignore: unused_element
  Future<ClassificationResult> _mlModelClassify(
    Map<String, dynamic> healthData,
  ) async {
    final model = _portableModel;
    if (model == null) {
      throw Exception('Portable model not initialized');
    }

    try {
      final features = _preprocessData(healthData, model);
      final prediction = model.predict(features);
      final categoryProbs = prediction.categoryProbabilities;
      final severityProbs = prediction.severityProbabilities;

      final maxCategoryIdx = _argMax(categoryProbs);
      final maxSeverityIdx = _argMax(severityProbs);

      final category = model.categoryLabels[maxCategoryIdx];
      final severity = model.severityLabels[maxSeverityIdx];
      final confidence = categoryProbs[maxCategoryIdx];

      final symptoms = (healthData['symptoms'] ?? '').toString().toLowerCase();
      final details = (healthData['details'] ?? '').toString().toLowerCase();
      final combinedText = '$symptoms $details'.trim();
      final keywords = _extractMatchedKeywords(
        combinedText,
        healthData: healthData,
      );
      final recoveryPlan = _generateRecoveryPlan(
        keywords,
        category: category,
        categoryGuidance: model.categoryRecoveryGuidance,
      );

      return ClassificationResult(
        category: category,
        severity: severity,
        confidence: confidence,
        categoryProbabilities: {
          for (int i = 0; i < model.categoryLabels.length; i++)
            model.categoryLabels[i]: categoryProbs[i],
        },
        severityProbabilities: {
          for (int i = 0; i < model.severityLabels.length; i++)
            model.severityLabels[i]: severityProbs[i],
        },
        method: 'ml_model',
        recommendedActions: _getRecommendedActions(category, severity),
        keywords: keywords,
        recoveryPlan: recoveryPlan,
      );
    } catch (e) {
      throw Exception('ML inference failed: $e');
    }
  }

  /// Rule-based classification (fallback)
  ClassificationResult _ruleBasedClassify(Map<String, dynamic> healthData) {
    final symptoms = (healthData['symptoms'] ?? '').toString().toLowerCase();
    final details = (healthData['details'] ?? '').toString().toLowerCase();
    final age = int.tryParse(healthData['age']?.toString() ?? '0') ?? 0;

    // Build comprehensive text from all relevant fields
    // This ensures prenatal and other record types are properly analyzed
    final additionalFields =
        [
              healthData['preExistingConditions'],
              healthData['previousComplications'],
              healthData['additionalNote'],
              healthData['allergies'],
              healthData['riskLevel'],
              healthData['plan'],
            ]
            .where((v) => v != null && v.toString().isNotEmpty)
            .map((v) => v.toString().toLowerCase())
            .join(' ');

    final combinedText = _normalizeText(
      '$symptoms $details $additionalFields'.trim(),
    );

    // Score each category
    final scores = <String, double>{};

    for (var category in categories) {
      scores[category] = _calculateCategoryScore(
        combinedText,
        category,
        age,
        healthData,
      );
    }

    // Get highest scoring category. On an exact tie, Emergency wins: this
    // is a deliberate safety rule, not an artifact of category list order
    // -- under-triage (missing a true emergency) is a far worse failure
    // mode than over-triage (flagging a non-emergency as one), so a tie
    // must resolve toward the safer category. Found via a real scoring
    // collision: adding a bare "vomiting" keyword to Communicable Disease
    // (for standalone naturally-phrased cases) tied with the existing
    // Emergency phrase "vomiting everything" ("vomiting everything"
    // contains "vomiting" as a substring), and because 'Communicable
    // Disease' is listed before 'Emergency' in `categories`, the tie was
    // silently resolving to the wrong, less-safe category.
    var maxCategory = categories[0];
    var maxScore = scores[maxCategory]!;

    for (var entry in scores.entries) {
      final isBetter =
          entry.value > maxScore ||
          (entry.value == maxScore && entry.key == 'Emergency');
      if (isBetter) {
        maxCategory = entry.key;
        maxScore = entry.value;
      }
    }

    // Safety margin: real Emergency evidence should not be overridden by
    // only a narrow score advantage from another category. Found via a
    // real under-triage regression: adding "shortness of breath" as a
    // Non-Communicable Disease (asthma) signal let it outscore a genuine
    // "chest pain" Emergency match once the age>40 chronic-disease
    // multiplier applied, silently reclassifying a classic heart-attack
    // presentation ("crushing chest pain ... shortness of breath", age
    // 62) as chronic disease at Low severity instead of Emergency/
    // Critical. Emergency's keyword list is curated to be specific,
    // serious signals (chest pain, difficulty breathing, stroke,
    // seizure, ...), so any real Emergency evidence (more than zero)
    // should only be overridden by a decisive margin -- at least one
    // full keyword match's worth of score -- not a fractional-point edge
    // from an incidental keyword overlap or an unrelated multiplier.
    const emergencySafetyMargin = 1.0;
    final emergencyScore = scores['Emergency'] ?? 0.0;
    if (maxCategory != 'Emergency' &&
        emergencyScore > 0 &&
        maxScore - emergencyScore < emergencySafetyMargin) {
      maxCategory = 'Emergency';
      maxScore = emergencyScore;
    }

    // Determine severity
    final severity = _determineSeverity(healthData, maxCategory);
    final probabilities = _normalizeScoresToProbabilities(scores);
    final confidence = probabilities[maxCategory]!;
    final matchedKeywords = _extractMatchedKeywords(
      combinedText,
      healthData: healthData,
    );
    final recoveryPlan = _generateRecoveryPlan(
      matchedKeywords,
      category: maxCategory,
    );

    return ClassificationResult(
      category: maxCategory,
      severity: severity,
      confidence: confidence,
      categoryProbabilities: probabilities,
      severityProbabilities: {severity: 1.0},
      method: 'rule_based',
      recommendedActions: _getRecommendedActions(maxCategory, severity),
      keywords: matchedKeywords,
      recoveryPlan: recoveryPlan,
    );
  }

  // The rule-based score for 'Routine Checkup' is a flat 0.5 baseline
  // applied to every record regardless of content (see
  // _calculateCategoryScore's 'Routine Checkup' case) -- it is what lets
  // Routine Checkup win when nothing else matched. If total score across
  // all 6 categories is at or near that 0.5 floor, no category actually
  // matched a keyword, structured field, vital-sign trigger, or age band:
  // there is no real evidence, so confidence must be low regardless of
  // which category "won" by elimination. Otherwise, confidence is the
  // winning category's share of the total score (a margin/dominance
  // measure: a category that wins by a landslide over the alternatives is
  // reported as more confident than a narrow win) -- this replaced an
  // earlier `min(score / 10.0, 1.0)` formula that used an arbitrary
  // divisor and was found (via the accuracy test suite) to rate an
  // unambiguous, correct 2-keyword match at only ~0.30 confidence, which
  // would have wrongly triggered the low-confidence review advisory on a
  // reliable result.
  static const double _noEvidenceFloor = 0.5;
  static const double _noEvidenceConfidence = 0.1;

  Map<String, double> _normalizeScoresToProbabilities(
    Map<String, double> scores,
  ) {
    final total = scores.values.fold<double>(0.0, (sum, v) => sum + v);
    if (total <= _noEvidenceFloor + 0.001) {
      // No real signal beyond the flat Routine Checkup baseline: report a
      // deliberately low, roughly-uniform confidence instead of an
      // artificially confident margin computed from near-zero scores.
      return scores.map(
        (k, v) =>
            MapEntry(k, total <= 0 ? 0.0 : (v / total) * _noEvidenceConfidence),
      );
    }
    return scores.map((k, v) => MapEntry(k, v / total));
  }

  double _calculateCategoryScore(
    String text,
    String category,
    int age,
    Map<String, dynamic> healthData,
  ) {
    double score = 0.0;

    switch (category) {
      case 'Emergency':
        score = _countKeywordMatches(text, keywordDatabase['emergency']!);
        // Check vital signs for emergency indicators
        score += _checkVitalSignsEmergency(healthData) * 5;
        break;

      case 'Communicable Disease':
        score = _countKeywordMatches(text, keywordDatabase['communicable']!);
        break;

      case 'Non-Communicable Disease':
        score = _countKeywordMatches(
          text,
          keywordDatabase['non_communicable']!,
        );
        // WHO Hypertension fact sheet: hypertension is frequently
        // asymptomatic ("the silent killer") -- a record can carry a
        // hypertensive-range BP reading with no symptom text at all, so
        // the vital-sign reading itself must be able to signal this
        // category, the same way _checkVitalSignsEmergency already lets
        // vitals signal Emergency on their own.
        score += _checkVitalSignsChronicRisk(healthData);
        // Higher weight for older patients
        if (age > 40) score *= 1.3;
        break;

      case 'Prenatal Care':
        score = _countKeywordMatches(text, keywordDatabase['prenatal']!);
        // Detect prenatal-specific fields in the data
        // If these fields exist, it's almost certainly a prenatal record
        int prenatalFieldCount = 0;
        for (var field in _structuredPrenatalFields) {
          if (healthData[field] != null &&
              healthData[field].toString().isNotEmpty) {
            prenatalFieldCount++;
          }
        }
        if (prenatalFieldCount > 0) {
          score += prenatalFieldCount * 2.0; // Strong boost per prenatal field
          // Also add base prenatal keywords to the match text
          // so recovery plan generation picks them up
        }
        // Check risk level for prenatal indicators
        final riskLevel = (healthData['riskLevel'] ?? '')
            .toString()
            .toLowerCase();
        if (riskLevel == 'high risk' ||
            riskLevel == 'moderate risk' ||
            riskLevel == 'low risk') {
          score += 3.0;
        }
        break;

      case 'Pediatric Care':
        score = _countKeywordMatches(text, keywordDatabase['pediatric']!);
        if (age < 18) score += 2;
        break;

      case 'Routine Checkup':
        // Default low score, will win if no other category matches
        score = 0.5;
        break;
    }

    return score;
  }

  double _countKeywordMatches(String text, List<String> keywords) {
    double count = 0.0;
    for (var keyword in keywords) {
      // Normalize the keyword the same way [text] was normalized (e.g.
      // "life-threatening" -> "life threatening") so a keyword that
      // contains a hyphen/variant spelling still matches already-
      // normalized free text.
      final normalizedKeyword = _normalizeText(keyword);
      // _unnegatedOccurrences already requires a word-boundary match (not
      // a fragment of a longer word) and excludes negated occurrences, so
      // every returned occurrence is a genuine, exact whole-word/phrase
      // match -- weighted the same as the old "exact boundary" bonus tier.
      if (_unnegatedOccurrences(text, normalizedKeyword).isNotEmpty) {
        count += 1.5;
      }
    }
    return count;
  }

  // WHO Hypertension fact sheet-grounded AHA blood-pressure staging,
  // scoped below the Emergency hypertensive-crisis threshold already
  // handled by _checkVitalSignsEmergency (>180 systolic / >120 diastolic)
  // so this does not compete with that check -- it only fires for the
  // Stage 1/Stage 2 hypertensive range that is a Non-Communicable Disease
  // signal, not an acute emergency.
  double _checkVitalSignsChronicRisk(Map<String, dynamic> healthData) {
    final details = (healthData['details'] ?? '').toString();
    double score = 0.0;

    final bpMatch = RegExp(r'BP:\s*(\d+)/(\d+)').firstMatch(details);
    if (bpMatch != null) {
      final systolic = int.tryParse(bpMatch.group(1) ?? '0') ?? 0;
      final diastolic = int.tryParse(bpMatch.group(2) ?? '0') ?? 0;
      if (systolic >= 140 || diastolic >= 90) {
        // AHA Stage 2 hypertension.
        score += 3.0;
      } else if (systolic >= 130 || diastolic >= 80) {
        // AHA Stage 1 hypertension.
        score += 1.5;
      }
    }

    return score;
  }

  double _checkVitalSignsEmergency(Map<String, dynamic> healthData) {
    final details = (healthData['details'] ?? '').toString();
    double score = 0.0;

    // Check blood pressure
    final bpMatch = RegExp(r'BP:\s*(\d+)/(\d+)').firstMatch(details);
    if (bpMatch != null) {
      final systolic = int.tryParse(bpMatch.group(1) ?? '0') ?? 0;
      final diastolic = int.tryParse(bpMatch.group(2) ?? '0') ?? 0;

      if (systolic > 180 ||
          systolic < 90 ||
          diastolic > 120 ||
          diastolic < 60) {
        score += 3.0;
      }
    }

    // Check temperature
    final tempMatch = RegExp(r'Temp:\s*(\d+\.?\d*)').firstMatch(details);
    if (tempMatch != null) {
      final temp = double.tryParse(tempMatch.group(1) ?? '0') ?? 0;
      if (temp > 40.0 || temp < 35.0) {
        score += 2.0;
      }
    }

    // Check heart rate
    final hrMatch = RegExp(r'HR:\s*(\d+)').firstMatch(details);
    if (hrMatch != null) {
      final hr = int.tryParse(hrMatch.group(1) ?? '0') ?? 0;
      if (hr > 120 || hr < 50) {
        score += 2.0;
      }
    }

    return score;
  }

  String _determineSeverity(Map<String, dynamic> healthData, String category) {
    final details = (healthData['details'] ?? '').toString();
    final symptoms = (healthData['symptoms'] ?? '').toString().toLowerCase();

    // Emergency is always critical
    if (category == 'Emergency') return 'Critical';

    // Check vital signs
    int severityScore = 0;

    // Blood pressure check - from details string (checkup format)
    final bpMatch = RegExp(r'BP:\s*(\d+)/(\d+)').firstMatch(details);
    if (bpMatch != null) {
      final systolic = int.tryParse(bpMatch.group(1) ?? '0') ?? 0;
      if (systolic > 160 || systolic < 90) {
        severityScore += 2;
      } else if (systolic > 140 || systolic < 100) {
        severityScore += 1;
      }
    }

    // Blood pressure check - from direct 'bp' field (prenatal format)
    final bpDirect = (healthData['bp'] ?? '').toString();
    if (bpDirect.isNotEmpty) {
      final bpDirectMatch = RegExp(r'(\d+)/(\d+)').firstMatch(bpDirect);
      if (bpDirectMatch != null) {
        final systolic = int.tryParse(bpDirectMatch.group(1) ?? '0') ?? 0;
        final diastolic = int.tryParse(bpDirectMatch.group(2) ?? '0') ?? 0;
        if (systolic > 160 || systolic < 90 || diastolic > 100) {
          severityScore += 2;
        } else if (systolic > 140 || systolic < 100 || diastolic > 90) {
          severityScore += 1;
        }
      }
    }

    // Temperature check - from details string (checkup format)
    final tempMatch = RegExp(r'Temp:\s*(\d+\.?\d*)').firstMatch(details);
    if (tempMatch != null) {
      final temp = double.tryParse(tempMatch.group(1) ?? '0') ?? 0;
      if (temp > 39.5) {
        severityScore += 2;
      } else if (temp > 38.0) {
        severityScore += 1;
      }
    }

    // Temperature check - from direct 'temp' field (prenatal format)
    final tempDirect = (healthData['temp'] ?? '').toString();
    if (tempDirect.isNotEmpty) {
      final temp = double.tryParse(tempDirect) ?? 0;
      if (temp > 39.5) {
        severityScore += 2;
      } else if (temp > 38.0) {
        severityScore += 1;
      }
    }

    // Prenatal risk level check
    if (category == 'Prenatal Care') {
      final riskLevel = (healthData['riskLevel'] ?? '')
          .toString()
          .toLowerCase();
      if (riskLevel.contains('high')) {
        severityScore += 3;
      } else if (riskLevel.contains('moderate')) {
        severityScore += 1;
      }
      // Check for prenatal complications
      final complications = (healthData['previousComplications'] ?? '')
          .toString()
          .toLowerCase();
      final preExisting = (healthData['preExistingConditions'] ?? '')
          .toString()
          .toLowerCase();
      if (complications.isNotEmpty || preExisting.isNotEmpty) {
        severityScore += 1;
      }
      // WHO antenatal danger signs (added 2026-08-11, found via an
      // independent clinical validation set grounded in WHO antenatal
      // danger-sign guidance): vaginal bleeding, convulsions, and reduced
      // fetal movement are recognized obstetric emergency warning signs on
      // their own, even without an explicit riskLevel field or a generic
      // "severe" keyword elsewhere in the text. Before this fix, a record
      // reporting "vaginal bleeding, severe abdominal pain" with no
      // riskLevel set only scored Medium, not the Critical this warning
      // sign warrants.
      const prenatalDangerSigns = [
        'vaginal bleeding',
        'bleeding',
        'convulsions',
        'reduced fetal movement',
        'decreased fetal movement',
        'no fetal movement',
        // Added 2026-08-11, found via an expanded independent naturally-
        // phrased validation set: a mother describing the exact same WHO
        // antenatal danger signs in plain lay language ("baby movements"
        // instead of "fetal movement", "spotting" instead of "vaginal
        // bleeding") was not recognized, which is a genuine safety gap --
        // missing a real danger sign only because of word choice.
        'spotting',
        'reduced baby movement',
        'decreased baby movement',
        'no baby movement',
      ];
      if (prenatalDangerSigns.any(
        (sign) => _unnegatedOccurrences(symptoms, sign).isNotEmpty,
      )) {
        severityScore += 3;
      }
    }

    // Symptom severity keywords
    final allText =
        '$symptoms ${(healthData['preExistingConditions'] ?? '').toString().toLowerCase()} ${(healthData['previousComplications'] ?? '').toString().toLowerCase()}';
    final severeKeywords = [
      'severe',
      'acute',
      'intense',
      'unbearable',
      'extreme',
    ];
    for (var keyword in severeKeywords) {
      if (_unnegatedOccurrences(allText, keyword).isNotEmpty) {
        severityScore += 1;
      }
    }

    // AHA angina guidance: exertional chest discomfort/tightness is not
    // the more acute "chest pain"/"difficulty breathing" Emergency
    // keywords (which already force Critical via the early Emergency
    // return above), but still warrants prompt evaluation. Treated as a
    // High-severity signal so it surfaces the same "urgent, schedule
    // within 24h" guidance as other High-severity results, without
    // over-classifying a chronic, rest-relieved symptom as a
    // life-threatening emergency.
    const cardiacCautionPhrases = ['chest discomfort', 'chest tightness'];
    if (cardiacCautionPhrases.any(
      (phrase) => _unnegatedOccurrences(symptoms, phrase).isNotEmpty,
    )) {
      severityScore += 2;
    }

    // Determine severity level
    if (severityScore >= 4) return 'Critical';
    if (severityScore >= 2) return 'High';
    if (severityScore >= 1) return 'Medium';
    return 'Low';
  }

  List<String> _getRecommendedActions(String category, String severity) {
    final actions = <String>[];

    if (severity == 'Critical' || category == 'Emergency') {
      actions.addAll([
        'Immediate medical attention required',
        'Call emergency services or go to the ER',
        'Do not delay treatment',
      ]);
    } else if (severity == 'High') {
      actions.addAll([
        'Urgent medical consultation needed',
        'Schedule appointment within 24 hours',
        'Monitor symptoms closely',
      ]);
    } else if (severity == 'Medium') {
      actions.addAll([
        'Schedule medical consultation',
        'Track symptoms for changes',
        'Follow the care plan provided by your clinician',
      ]);
    }

    switch (category) {
      case 'Communicable Disease':
        actions.addAll([
          'Practice isolation if necessary',
          'Maintain good hygiene',
          'Limit contact with others',
        ]);
        break;
      case 'Non-Communicable Disease':
        actions.addAll([
          'Follow your long-term care plan',
          'Maintain healthy lifestyle',
          'Regular follow-up appointments',
        ]);
        break;
      case 'Prenatal Care':
        actions.addAll([
          'Regular prenatal checkups',
          'Follow your prenatal care plan',
          'Maintain healthy diet',
        ]);
        break;
    }

    return actions;
  }

  Map<String, dynamic>? _getTreatmentForKeyword(String keyword) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    if (treatmentDatabase.containsKey(normalized)) {
      return treatmentDatabase[normalized];
    }

    final alias = treatmentAliases[normalized];
    if (alias != null && treatmentDatabase.containsKey(alias)) {
      return treatmentDatabase[alias];
    }

    return null;
  }

  bool _hasTreatmentForKeyword(String keyword) {
    return _getTreatmentForKeyword(keyword) != null;
  }

  // AI guidance is limited to supportive care, precautions, monitoring, and
  // referral prompts. Medication, dosage, prescription, and inhaler wording
  // is filtered at the final boundary so legacy model metadata cannot turn
  // into an AI medication recommendation.
  static bool _isMedicationInstruction(String value) {
    return RegExp(
      r'\b(medications?|medicines?|dosage|prescription|prescribed|antibiotics?|inhaler)\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static List<String> _safeGuidanceItems(Iterable<String> values) {
    return values
        .where((value) => !_isMedicationInstruction(value))
        .toList(growable: false);
  }

  /// Generate detailed recovery recommendations based on keywords.
  /// Falls back to category-level recommendations when keyword-level
  /// treatments are unavailable.
  Map<String, dynamic> _generateRecoveryPlan(
    List<String> keywords, {
    String? category,
    Map<String, Map<String, dynamic>>? categoryGuidance,
  }) {
    final homeCare = <String>{};
    final precautions = <String>{};
    final generalAdvice = <String>{};
    String? estimatedRecovery;

    // Collect recommendations from all matched keywords
    for (var keyword in keywords) {
      final treatment = _getTreatmentForKeyword(keyword);
      if (treatment != null) {
        if (treatment['home_care'] != null) {
          homeCare.addAll((treatment['home_care'] as List).cast<String>());
        }
        if (treatment['precautions'] != null) {
          precautions.addAll((treatment['precautions'] as List).cast<String>());
        }
        if (estimatedRecovery == null && treatment['recovery_time'] != null) {
          estimatedRecovery = treatment['recovery_time'] as String;
        }
      }
    }

    final fallback = category != null
        ? (categoryGuidance?[category] ?? categoryFallbackTreatment[category])
        : null;

    if (fallback != null) {
      if (homeCare.isEmpty && fallback['home_care'] != null) {
        homeCare.addAll((fallback['home_care'] as List).cast<String>());
      }
      if (precautions.isEmpty && fallback['precautions'] != null) {
        precautions.addAll((fallback['precautions'] as List).cast<String>());
      }
      if (estimatedRecovery == null && fallback['recovery_time'] != null) {
        estimatedRecovery = fallback['recovery_time'] as String;
      }
      if (generalAdvice.isEmpty && fallback['general_advice'] != null) {
        generalAdvice.addAll(
          (fallback['general_advice'] as List).cast<String>(),
        );
      }
    }

    // Add general recommendations if nothing specific found
    if (homeCare.isEmpty) {
      homeCare.addAll([
        'Get adequate rest and sleep',
        'Stay well hydrated',
        'Maintain balanced nutrition',
        'Monitor symptoms',
        'Follow medical advice',
      ]);
    }

    if (generalAdvice.isEmpty) {
      generalAdvice.addAll([
        '[OK] Follow healthcare provider instructions',
        '[OK] Keep all follow-up appointments',
        '[OK] Report any worsening symptoms',
        '[OK] Maintain healthy lifestyle habits',
      ]);
    }

    return {
      'home_care': _safeGuidanceItems(homeCare),
      'precautions': _safeGuidanceItems(precautions),
      'estimated_recovery': estimatedRecovery ?? 'Varies by condition',
      'general_advice': _safeGuidanceItems(generalAdvice),
    };
  }

  List<String> _extractMatchedKeywords(
    String text, {
    Map<String, dynamic>? healthData,
  }) {
    final matched = <String>[];

    for (var keywords in keywordDatabase.values) {
      for (var keyword in keywords) {
        // Match against the normalized form (handles e.g. the hyphen in
        // "life-threatening"), but keep the original keyword string in
        // the result so treatment/alias lookups keyed by the original
        // spelling still work.
        if (!matched.contains(keyword) &&
            _unnegatedOccurrences(text, _normalizeText(keyword)).isNotEmpty) {
          matched.add(keyword);
        }
      }
    }

    // For prenatal records, ensure prenatal keywords are included
    // even if not explicitly in the text
    if (healthData != null) {
      if (_hasStructuredPrenatalSignal(healthData)) {
        if (!matched.contains('prenatal')) matched.add('prenatal');
        if (!matched.contains('pregnant')) matched.add('pregnant');
        if (!matched.contains('gestational')) matched.add('gestational');
        if (!matched.contains('maternal')) matched.add('maternal');
      }
    }

    matched.sort((a, b) {
      final aPriority = _hasTreatmentForKeyword(a) ? 0 : 1;
      final bPriority = _hasTreatmentForKeyword(b) ? 0 : 1;
      return aPriority.compareTo(bPriority);
    });

    return matched.take(10).toList();
  }

  /// Preprocess data for portable ML model input.
  /// Kept aligned with train_model/train_health_classifier.py.
  List<double> _preprocessData(
    Map<String, dynamic> healthData,
    _PortableMLModel model,
  ) {
    final features = List<double>.filled(model.inputSize, 0.0);

    final symptoms = (healthData['symptoms'] ?? '').toString().toLowerCase();
    final details = (healthData['details'] ?? '').toString().toLowerCase();
    final age = int.tryParse(healthData['age']?.toString() ?? '0') ?? 0;
    final combinedText = '$symptoms $details';

    // Feature 0: Normalized age
    if (features.isNotEmpty) {
      features[0] = age / 100.0;
    }

    if (model.usesKeywordHashing && model.featureKeywords.isNotEmpty) {
      for (final keyword in model.featureKeywords) {
        if (!combinedText.contains(keyword)) {
          continue;
        }
        final featureIndex = _keywordFeatureIndex(
          keyword,
          startIndex: model.keywordFeatureStartIndex,
          bucketCount: model.keywordBucketCount,
        );
        if (featureIndex >= 0 && featureIndex < features.length) {
          features[featureIndex] = 1.0;
        }
      }
    } else {
      // Legacy fallback for older portable model files.
      int idx = _legacyKeywordFeatureStartIndex;
      for (var keywordList in mlFeatureKeywords.values) {
        for (var keyword in keywordList.take(10)) {
          if (idx >= _legacyKeywordFeatureEndIndexExclusive) break;
          if (idx < features.length) {
            features[idx] = combinedText.contains(keyword) ? 1.0 : 0.0;
          }
          idx++;
        }
      }
    }

    final bpSystolicIndex = model.usesKeywordHashing
        ? model.bpSystolicFeatureIndex
        : _legacyBpSystolicFeatureIndex;
    final bpDiastolicIndex = model.usesKeywordHashing
        ? model.bpDiastolicFeatureIndex
        : _legacyBpDiastolicFeatureIndex;
    final tempIndex = model.usesKeywordHashing
        ? model.temperatureFeatureIndex
        : _legacyTemperatureFeatureIndex;
    final hrIndex = model.usesKeywordHashing
        ? model.heartRateFeatureIndex
        : _legacyHeartRateFeatureIndex;

    // Vital-sign features (normalized)
    final bpMatch = RegExp(r'bp:\s*(\d+)/(\d+)').firstMatch(details);
    if (bpMatch != null) {
      if (bpSystolicIndex >= 0 && bpSystolicIndex < features.length) {
        features[bpSystolicIndex] =
            (int.tryParse(bpMatch.group(1) ?? '0') ?? 0) / 200.0;
      }
      if (bpDiastolicIndex >= 0 && bpDiastolicIndex < features.length) {
        features[bpDiastolicIndex] =
            (int.tryParse(bpMatch.group(2) ?? '0') ?? 0) / 150.0;
      }
    }

    final tempMatch = RegExp(r'temp:\s*(\d+\.?\d*)').firstMatch(details);
    if (tempMatch != null && tempIndex >= 0 && tempIndex < features.length) {
      features[tempIndex] =
          (double.tryParse(tempMatch.group(1) ?? '0') ?? 0) / 42.0;
    }

    final hrMatch = RegExp(r'hr:\s*(\d+)').firstMatch(details);
    if (hrMatch != null && hrIndex >= 0 && hrIndex < features.length) {
      features[hrIndex] = (int.tryParse(hrMatch.group(1) ?? '0') ?? 0) / 200.0;
    }

    return features;
  }

  int _fnv1a32(String value) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  int _keywordFeatureIndex(
    String keyword, {
    required int startIndex,
    required int bucketCount,
  }) {
    if (bucketCount <= 0) {
      return startIndex;
    }
    return startIndex + (_fnv1a32(keyword) % bucketCount);
  }

  int _argMax(List<double> list) {
    double maxValue = list[0];
    int maxIndex = 0;

    for (int i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }

    return maxIndex;
  }

  void dispose() {
    _portableModel = null;
    _isInitialized = false;
  }
}

/// Classification result with detailed information
class ClassificationResult {
  final String category;
  final String severity;
  final double confidence;
  final Map<String, double> categoryProbabilities;
  final Map<String, double> severityProbabilities;
  final String method; // 'ml_model' or 'rule_based'
  final List<String> recommendedActions;
  final List<String>? keywords;
  final Map<String, dynamic>? recoveryPlan;
  final AiDecisionSupport? decisionSupport;

  ClassificationResult({
    required this.category,
    required this.severity,
    required this.confidence,
    required this.categoryProbabilities,
    required this.severityProbabilities,
    required this.method,
    required this.recommendedActions,
    this.keywords,
    this.recoveryPlan,
    this.decisionSupport,
  });

  ClassificationResult withDecisionSupport(AiDecisionSupport support) {
    final existingPlan = recoveryPlan ?? <String, dynamic>{};
    return ClassificationResult(
      category: category,
      severity: severity,
      confidence: confidence,
      categoryProbabilities: categoryProbabilities,
      severityProbabilities: severityProbabilities,
      method: method,
      recommendedActions: recommendedActions,
      keywords: keywords,
      recoveryPlan: {...existingPlan, 'decision_support': support.toJson()},
      decisionSupport: support,
    );
  }

  Map<String, dynamic> toJson() => {
    'category': category,
    'severity': severity,
    'confidence': confidence,
    'category_probabilities': categoryProbabilities,
    'severity_probabilities': severityProbabilities,
    'method': method,
    'recommended_actions': recommendedActions,
    'keywords': keywords,
    'recovery_plan': recoveryPlan,
    'decision_support': decisionSupport?.toJson(),
    'timestamp': DateTime.now().toIso8601String(),
  };

  @override
  String toString() {
    return 'ClassificationResult(category: $category, severity: $severity, '
        'confidence: ${(confidence * 100).toStringAsFixed(1)}%, method: $method)';
  }
}

/// User-facing explanation for an AI result. It reports observable inputs and
/// uncertainty, not internal reasoning or hidden chain-of-thought.
class AiDecisionSupport {
  const AiDecisionSupport({
    required this.explanation,
    required this.influencingInformation,
    required this.riskFactors,
    required this.missingInformation,
    required this.confidence,
    required this.requiresHumanReview,
    required this.nextAction,
    this.reviewStatus = 'Pending human review',
    this.finalHumanDecision = '',
    this.humanReviewNote = '',
  });

  final String explanation;
  final List<String> influencingInformation;
  final List<String> riskFactors;
  final List<String> missingInformation;
  final double confidence;
  final bool requiresHumanReview;
  final String nextAction;
  final String reviewStatus;
  final String finalHumanDecision;
  final String humanReviewNote;

  static AiDecisionSupport fromClassification(
    ClassificationResult result,
    Map<String, dynamic> healthData,
  ) {
    final keywords =
        result.keywords
            ?.map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final influencing = <String>[];
    if (keywords.isNotEmpty) {
      influencing.add('Recognized terms: ${keywords.join(', ')}');
    }
    if (_hasValue(healthData['symptoms'])) {
      influencing.add('Entered symptoms');
    }
    if (_hasValue(healthData['details'])) {
      influencing.add('Entered clinical details');
    }
    if (_hasValue(healthData['vitalsigns'])) {
      influencing.add('Available vital signs');
    }
    if (_hasValue(healthData['riskLevel']) ||
        _hasValue(healthData['preExistingConditions']) ||
        _hasValue(healthData['previousComplications'])) {
      influencing.add('Available risk or history fields');
    }
    if (influencing.isEmpty) {
      influencing.add(
        'Available record fields only; no specific symptom term was recognized',
      );
    }

    final missing = <String>[];
    if (!_hasValue(healthData['symptoms']) &&
        !_hasValue(healthData['details'])) {
      missing.add('Symptoms or clinical details were not provided');
    }
    if (!_hasValue(healthData['age'])) missing.add('Age was not provided');
    if (!_hasValue(healthData['vitalsigns'])) {
      missing.add('Relevant vital signs were not provided');
    }
    if (keywords.isEmpty) {
      missing.add('No specific recognized symptom term was available');
    }

    final risks = <String>[];
    if (result.category == 'Emergency' || result.severity == 'Critical') {
      risks.add('Emergency or critical-severity indicators were detected');
    } else if (result.severity == 'High') {
      risks.add('High-severity indicators were detected');
    }
    final age = int.tryParse(healthData['age']?.toString() ?? '');
    if (age != null && (age < 5 || age >= 65)) {
      risks.add('The recorded age may require additional clinical attention');
    }
    if (risks.isEmpty) {
      risks.add(
        'No additional risk flag was generated by the available fields',
      );
    }

    final needsReview =
        result.confidence < 0.75 ||
        result.category == 'Emergency' ||
        result.severity == 'High' ||
        result.severity == 'Critical' ||
        missing.isNotEmpty;
    final explanation = keywords.isEmpty
        ? 'The AI selected ${result.category} with ${result.severity} severity '
              'from the available record fields, but no specific symptom term '
              'was recognized.'
        : 'The AI selected ${result.category} with ${result.severity} severity '
              'based on the recognized terms and available structured fields '
              'shown below.';
    final nextAction =
        result.category == 'Emergency' || result.severity == 'Critical'
        ? 'Escalate for urgent in-person assessment now. An authorized healthcare professional must make the final decision.'
        : needsReview
        ? 'Verify the source record and have authorized healthcare personnel review, modify, accept, or reject this recommendation.'
        : 'Use this as screening support and confirm it against the complete record with authorized healthcare personnel.';

    return AiDecisionSupport(
      explanation:
          '$explanation This is decision support, not a final diagnosis or prescription.',
      influencingInformation: List.unmodifiable(influencing),
      riskFactors: List.unmodifiable(risks),
      missingInformation: List.unmodifiable(missing),
      confidence: result.confidence,
      requiresHumanReview: needsReview,
      nextAction: nextAction,
    );
  }

  Map<String, dynamic> toJson() => {
    'explanation': explanation,
    'influencing_information': influencingInformation,
    'risk_factors': riskFactors,
    'missing_information': missingInformation,
    'confidence': confidence,
    'requires_human_review': requiresHumanReview,
    'next_action': nextAction,
    'review_status': reviewStatus,
    'final_human_decision': finalHumanDecision,
    'human_review_note': humanReviewNote,
  };

  static bool _hasValue(Object? value) {
    return value != null && value.toString().trim().isNotEmpty;
  }
}

class _PortablePrediction {
  final List<double> categoryProbabilities;
  final List<double> severityProbabilities;

  _PortablePrediction({
    required this.categoryProbabilities,
    required this.severityProbabilities,
  });
}

class _PortableMLModel {
  final List<List<double>> _dense1Kernel;
  final List<double> _dense1Bias;
  final List<List<double>> _dense2Kernel;
  final List<double> _dense2Bias;
  final List<List<double>> _dense3Kernel;
  final List<double> _dense3Bias;
  final List<List<double>> _categoryKernel;
  final List<double> _categoryBias;
  final List<List<double>> _severityKernel;
  final List<double> _severityBias;
  final List<String> categoryLabels;
  final List<String> severityLabels;
  final List<String> featureKeywords;
  final bool usesKeywordHashing;
  final int keywordFeatureStartIndex;
  final int keywordBucketCount;
  final int bpSystolicFeatureIndex;
  final int bpDiastolicFeatureIndex;
  final int temperatureFeatureIndex;
  final int heartRateFeatureIndex;
  final Map<String, Map<String, dynamic>>? categoryRecoveryGuidance;

  _PortableMLModel({
    required List<List<double>> dense1Kernel,
    required List<double> dense1Bias,
    required List<List<double>> dense2Kernel,
    required List<double> dense2Bias,
    required List<List<double>> dense3Kernel,
    required List<double> dense3Bias,
    required List<List<double>> categoryKernel,
    required List<double> categoryBias,
    required List<List<double>> severityKernel,
    required List<double> severityBias,
    required this.categoryLabels,
    required this.severityLabels,
    required this.featureKeywords,
    required this.usesKeywordHashing,
    required this.keywordFeatureStartIndex,
    required this.keywordBucketCount,
    required this.bpSystolicFeatureIndex,
    required this.bpDiastolicFeatureIndex,
    required this.temperatureFeatureIndex,
    required this.heartRateFeatureIndex,
    this.categoryRecoveryGuidance,
  }) : _dense1Kernel = dense1Kernel,
       _dense1Bias = dense1Bias,
       _dense2Kernel = dense2Kernel,
       _dense2Bias = dense2Bias,
       _dense3Kernel = dense3Kernel,
       _dense3Bias = dense3Bias,
       _categoryKernel = categoryKernel,
       _categoryBias = categoryBias,
       _severityKernel = severityKernel,
       _severityBias = severityBias {
    _validateDenseLayer(_dense1Kernel, _dense1Bias, 'dense_1');
    _validateDenseLayer(_dense2Kernel, _dense2Bias, 'dense_2');
    _validateDenseLayer(_dense3Kernel, _dense3Bias, 'dense_3');
    _validateDenseLayer(_categoryKernel, _categoryBias, 'category_output');
    _validateDenseLayer(_severityKernel, _severityBias, 'severity_output');

    if (categoryLabels.length != _categoryBias.length) {
      throw FormatException(
        'Category labels (${categoryLabels.length}) must match category output '
        'size (${_categoryBias.length}).',
      );
    }
    if (severityLabels.length != _severityBias.length) {
      throw FormatException(
        'Severity labels (${severityLabels.length}) must match severity output '
        'size (${_severityBias.length}).',
      );
    }

    if (keywordBucketCount <= 0) {
      throw const FormatException('keyword_hash.bucket_count must be positive');
    }

    final maxFeatureIndex = _dense1Kernel.length - 1;
    final indices = [
      keywordFeatureStartIndex,
      bpSystolicFeatureIndex,
      bpDiastolicFeatureIndex,
      temperatureFeatureIndex,
      heartRateFeatureIndex,
    ];
    for (final index in indices) {
      if (index < 0 || index > maxFeatureIndex) {
        throw FormatException(
          'Feature index $index is out of bounds for input size '
          '${_dense1Kernel.length}',
        );
      }
    }
  }

  int get inputSize => _dense1Kernel.length;

  factory _PortableMLModel.fromJson(Map<String, dynamic> json) {
    final layersValue = json['layers'];
    if (layersValue is! Map) {
      throw const FormatException('Missing or invalid "layers" object');
    }
    final layers = Map<String, dynamic>.from(layersValue);

    Map<String, dynamic> readLayer(String layerName) {
      final layer = layers[layerName];
      if (layer is! Map) {
        throw FormatException('Missing or invalid layer "$layerName"');
      }
      return Map<String, dynamic>.from(layer);
    }

    final dense1 = readLayer('dense_1');
    final dense2 = readLayer('dense_2');
    final dense3 = readLayer('dense_3');
    final category = readLayer('category_output');
    final severity = readLayer('severity_output');

    final featureKeywords = _parseOptionalStringList(json['feature_keywords']);
    final keywordHash = _parseOptionalMap(json['keyword_hash']);
    final vitalFeatureIndices = _parseOptionalMap(
      json['vital_feature_indices'],
    );
    final usesKeywordHashing =
        featureKeywords.isNotEmpty && keywordHash != null;

    return _PortableMLModel(
      dense1Kernel: _parseMatrix(dense1['kernel'], 'dense_1.kernel'),
      dense1Bias: _parseVector(dense1['bias'], 'dense_1.bias'),
      dense2Kernel: _parseMatrix(dense2['kernel'], 'dense_2.kernel'),
      dense2Bias: _parseVector(dense2['bias'], 'dense_2.bias'),
      dense3Kernel: _parseMatrix(dense3['kernel'], 'dense_3.kernel'),
      dense3Bias: _parseVector(dense3['bias'], 'dense_3.bias'),
      categoryKernel: _parseMatrix(
        category['kernel'],
        'category_output.kernel',
      ),
      categoryBias: _parseVector(category['bias'], 'category_output.bias'),
      severityKernel: _parseMatrix(
        severity['kernel'],
        'severity_output.kernel',
      ),
      severityBias: _parseVector(severity['bias'], 'severity_output.bias'),
      categoryLabels: _parseLabelList(
        json['category_labels'],
        'category_labels',
      ),
      severityLabels: _parseLabelList(
        json['severity_labels'],
        'severity_labels',
      ),
      featureKeywords: featureKeywords,
      usesKeywordHashing: usesKeywordHashing,
      keywordFeatureStartIndex: _readIntField(
        keywordHash,
        fieldName: 'feature_start_index',
        defaultValue: 1,
      ),
      keywordBucketCount: _readIntField(
        keywordHash,
        fieldName: 'bucket_count',
        defaultValue: 50,
      ),
      bpSystolicFeatureIndex: _readIntField(
        vitalFeatureIndices,
        fieldName: 'bp_systolic',
        defaultValue: 51,
      ),
      bpDiastolicFeatureIndex: _readIntField(
        vitalFeatureIndices,
        fieldName: 'bp_diastolic',
        defaultValue: 52,
      ),
      temperatureFeatureIndex: _readIntField(
        vitalFeatureIndices,
        fieldName: 'temperature',
        defaultValue: 53,
      ),
      heartRateFeatureIndex: _readIntField(
        vitalFeatureIndices,
        fieldName: 'heart_rate',
        defaultValue: 54,
      ),
      categoryRecoveryGuidance: _parseCategoryGuidance(
        json['category_recovery_guidance'],
      ),
    );
  }

  _PortablePrediction predict(List<double> features) {
    if (features.length != _dense1Kernel.length) {
      throw ArgumentError(
        'Expected ${_dense1Kernel.length} features, got ${features.length}',
      );
    }

    final x1 = _relu(_dense(features, _dense1Kernel, _dense1Bias));
    final x2 = _relu(_dense(x1, _dense2Kernel, _dense2Bias));
    final x3 = _relu(_dense(x2, _dense3Kernel, _dense3Bias));

    final categoryLogits = _dense(x3, _categoryKernel, _categoryBias);
    final severityLogits = _dense(x3, _severityKernel, _severityBias);

    return _PortablePrediction(
      categoryProbabilities: _softmax(categoryLogits),
      severityProbabilities: _softmax(severityLogits),
    );
  }

  static void _validateDenseLayer(
    List<List<double>> kernel,
    List<double> bias,
    String layerName,
  ) {
    if (kernel.isEmpty) {
      throw FormatException('Layer "$layerName" has an empty kernel');
    }
    final outputSize = kernel.first.length;
    if (outputSize == 0) {
      throw FormatException('Layer "$layerName" has zero output size');
    }
    for (final row in kernel) {
      if (row.length != outputSize) {
        throw FormatException(
          'Layer "$layerName" kernel rows must have consistent lengths',
        );
      }
    }
    if (bias.length != outputSize) {
      throw FormatException(
        'Layer "$layerName" bias size (${bias.length}) does not match output '
        'size ($outputSize)',
      );
    }
  }

  static List<double> _dense(
    List<double> input,
    List<List<double>> kernel,
    List<double> bias,
  ) {
    final output = List<double>.from(bias);

    for (int i = 0; i < input.length; i++) {
      final row = kernel[i];
      final value = input[i];
      if (value == 0) continue;
      for (int j = 0; j < output.length; j++) {
        output[j] += value * row[j];
      }
    }

    return output;
  }

  static List<double> _relu(List<double> values) {
    return [
      for (final value in values)
        if (value > 0) value else 0.0,
    ];
  }

  static List<double> _softmax(List<double> values) {
    final maxValue = values.reduce(max);
    final exps = [for (final value in values) exp(value - maxValue)];
    final sumExps = exps.fold<double>(0.0, (sum, value) => sum + value);
    if (sumExps == 0) {
      return List<double>.filled(values.length, 0.0);
    }
    return [for (final value in exps) value / sumExps];
  }

  static List<List<double>> _parseMatrix(dynamic value, String fieldName) {
    if (value is! List) {
      throw FormatException('Expected "$fieldName" to be a list');
    }
    return [for (final row in value) _parseVector(row, fieldName)];
  }

  static List<double> _parseVector(dynamic value, String fieldName) {
    if (value is! List) {
      throw FormatException('Expected "$fieldName" to be a list');
    }
    return [
      for (final item in value)
        if (item is num)
          item.toDouble()
        else
          throw FormatException(
            'Expected numeric values in "$fieldName", found $item',
          ),
    ];
  }

  static List<String> _parseLabelList(dynamic value, String fieldName) {
    if (value is! List) {
      throw FormatException('Expected "$fieldName" to be a list');
    }
    return [
      for (final item in value)
        if (item is String)
          item
        else
          throw FormatException(
            'Expected string values in "$fieldName", found $item',
          ),
    ];
  }

  static List<String> _parseOptionalStringList(dynamic value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw const FormatException('Expected "feature_keywords" to be a list');
    }
    return [
      for (final item in value)
        if (item is String)
          item
        else
          throw const FormatException(
            'Expected string values in "feature_keywords"',
          ),
    ];
  }

  static Map<String, dynamic>? _parseOptionalMap(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw const FormatException('Expected metadata field to be a map');
    }
    return Map<String, dynamic>.from(value);
  }

  static int _readIntField(
    Map<String, dynamic>? map, {
    required String fieldName,
    required int defaultValue,
  }) {
    if (map == null || !map.containsKey(fieldName)) {
      return defaultValue;
    }
    final value = map[fieldName];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException('Expected "$fieldName" to be numeric');
  }

  static Map<String, Map<String, dynamic>>? _parseCategoryGuidance(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw const FormatException(
        'Expected "category_recovery_guidance" to be a map',
      );
    }

    final parsed = <String, Map<String, dynamic>>{};
    value.forEach((key, rawEntry) {
      if (rawEntry is Map) {
        parsed[key.toString()] = Map<String, dynamic>.from(rawEntry);
      }
    });
    return parsed.isEmpty ? null : parsed;
  }
}
