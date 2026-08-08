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
      'medications': ['Paracetamol/Acetaminophen', 'Ibuprofen'],
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
      'medications': ['Cough suppressants', 'Expectorants', 'Honey (natural)'],
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
      'medications': ['As prescribed by emergency physician'],
      'home_care': ['SEEK IMMEDIATE MEDICAL ATTENTION'],
      'precautions': [
        'Call emergency services immediately',
        'Do not drive yourself',
        'Chew aspirin if not allergic',
      ],
      'recovery_time': 'Requires immediate medical evaluation',
    },
    'diabetes': {
      'medications': [
        'Metformin',
        'Insulin (as prescribed)',
        'Other oral hypoglycemics',
      ],
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
      'medications': [
        'ACE inhibitors',
        'Beta blockers',
        'Calcium channel blockers',
      ],
      'home_care': [
        'Reduce sodium intake (<2000mg/day)',
        'DASH diet (fruits, vegetables, whole grains)',
        'Regular exercise (150 min/week)',
        'Limit alcohol consumption',
        'Manage stress through relaxation',
        'Monitor BP daily',
      ],
      'precautions': ['Never stop medications without doctor consultation'],
      'recovery_time': 'Lifelong management',
    },
    'pneumonia': {
      'medications': ['Antibiotics', 'Fever reducers', 'Pain relievers'],
      'home_care': [
        'Complete full course of antibiotics',
        'Rest adequately',
        'Drink plenty of fluids',
        'Use humidifier',
        'Practice deep breathing exercises',
      ],
      'precautions': ['Follow up chest X-ray after 6 weeks'],
      'recovery_time': '2-4 weeks',
    },
    'asthma': {
      'medications': [
        'Inhalers (bronchodilators)',
        'Corticosteroids',
        'Controller medications',
      ],
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
      'medications': [
        'Oral rehydration solution',
        'Loperamide (if appropriate)',
      ],
      'home_care': [
        'Stay well hydrated (ORS, clear fluids)',
        'BRAT diet (Bananas, Rice, Applesauce, Toast)',
        'Avoid dairy temporarily',
        'Maintain hand hygiene',
        'Rest adequately',
      ],
      'precautions': ['Seek help if blood in stool or severe dehydration'],
      'recovery_time': '2-7 days',
    },
    'pregnant': {
      'medications': ['Prenatal vitamins', 'Folic acid', 'Iron supplements'],
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
      'medications': [
        'Prenatal vitamins',
        'Folic acid',
        'Iron supplements',
        'Calcium supplements',
      ],
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
      'medications': ['Prenatal vitamins', 'Iron supplements', 'Folic acid'],
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
      'medications': ['Prenatal vitamins', 'Folic acid', 'Iron supplements'],
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
      'medications': [
        'Use symptom-relief medicines only as prescribed by a clinician',
      ],
      'home_care': [
        'Rest and stay hydrated',
        'Monitor symptoms daily',
        'Practice hygiene and reduce close contact when contagious',
      ],
      'precautions': ['Seek consultation if symptoms worsen or persist'],
      'recovery_time': 'Usually days to weeks depending on infection',
    },
    'Non-Communicable Disease': {
      'medications': ['Continue maintenance medications as prescribed'],
      'home_care': [
        'Follow diet and lifestyle plan',
        'Track blood pressure/glucose as advised',
        'Keep scheduled follow-up visits',
      ],
      'precautions': ['Do not stop long-term medications without advice'],
      'recovery_time': 'Ongoing long-term management',
    },
    'Emergency': {
      'medications': ['Do not self-medicate before emergency assessment'],
      'home_care': ['Seek urgent in-person care immediately'],
      'precautions': ['Call emergency services for severe or sudden symptoms'],
      'recovery_time': 'Requires immediate professional evaluation',
    },
    'Routine Checkup': {
      'medications': ['No medication unless prescribed after evaluation'],
      'home_care': [
        'Maintain hydration, sleep, and balanced nutrition',
        'Continue preventive screening as scheduled',
      ],
      'precautions': ['Return for review if new symptoms appear'],
      'recovery_time': 'No acute recovery needed',
    },
    'Prenatal Care': {
      'medications': ['Prenatal supplements as prescribed'],
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
      'medications': ['Use pediatric-dose medicines only as prescribed'],
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
    if (_portableModel != null) {
      try {
        result = await _mlModelClassify(healthData);
      } catch (e) {
        debugPrint('[AI] ML inference failed, falling back to rule-based: $e');
        result = _ruleBasedClassify(healthData);
      }
    } else {
      result = _ruleBasedClassify(healthData);
    }

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

  /// Classify using portable ML model.
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

    final combinedText = '$symptoms $details $additionalFields'.trim();

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

    // Get highest scoring category
    var maxCategory = categories[0];
    var maxScore = scores[maxCategory]!;

    for (var entry in scores.entries) {
      if (entry.value > maxScore) {
        maxCategory = entry.key;
        maxScore = entry.value;
      }
    }

    // Determine severity
    final severity = _determineSeverity(healthData, maxCategory);
    final confidence = min(maxScore / 10.0, 1.0); // Normalize to 0-1
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
      categoryProbabilities: scores.map(
        (k, v) => MapEntry(k, min(v / 10.0, 1.0)),
      ),
      severityProbabilities: {severity: 1.0},
      method: 'rule_based',
      recommendedActions: _getRecommendedActions(maxCategory, severity),
      keywords: matchedKeywords,
      recoveryPlan: recoveryPlan,
    );
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
        // Higher weight for older patients
        if (age > 40) score *= 1.3;
        break;

      case 'Prenatal Care':
        score = _countKeywordMatches(text, keywordDatabase['prenatal']!);
        // Detect prenatal-specific fields in the data
        // If these fields exist, it's almost certainly a prenatal record
        final prenatalFields = [
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
        int prenatalFieldCount = 0;
        for (var field in prenatalFields) {
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
      if (text.contains(keyword)) {
        count += 1.0;
        // Bonus for exact word match
        if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(text)) {
          count += 0.5;
        }
      }
    }
    return count;
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
      if (allText.contains(keyword)) severityScore += 1;
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
        '🚨 Immediate medical attention required',
        '📞 Call emergency services or go to ER',
        '⚕️ Do not delay treatment',
      ]);
    } else if (severity == 'High') {
      actions.addAll([
        '⚠️ Urgent medical consultation needed',
        '📅 Schedule appointment within 24 hours',
        '📋 Monitor symptoms closely',
      ]);
    } else if (severity == 'Medium') {
      actions.addAll([
        '👨‍⚕️ Schedule medical consultation',
        '📊 Track symptoms for changes',
        '📝 Follow the care plan provided by your clinician',
      ]);
    }

    switch (category) {
      case 'Communicable Disease':
        actions.addAll([
          '😷 Practice isolation if necessary',
          '🧼 Maintain good hygiene',
          '👥 Limit contact with others',
        ]);
        break;
      case 'Non-Communicable Disease':
        actions.addAll([
          '🩺 Follow your long-term care plan',
          '🏃 Maintain healthy lifestyle',
          '📅 Regular follow-up appointments',
        ]);
        break;
      case 'Prenatal Care':
        actions.addAll([
          '🤰 Regular prenatal checkups',
          '📘 Follow your prenatal care plan',
          '🥗 Maintain healthy diet',
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
      'home_care': homeCare.toList(),
      'precautions': precautions.toList(),
      'estimated_recovery': estimatedRecovery ?? 'Varies by condition',
      'general_advice': generalAdvice.toList(),
    };
  }

  List<String> _extractMatchedKeywords(
    String text, {
    Map<String, dynamic>? healthData,
  }) {
    final matched = <String>[];

    for (var keywords in keywordDatabase.values) {
      for (var keyword in keywords) {
        if (text.contains(keyword) && !matched.contains(keyword)) {
          matched.add(keyword);
        }
      }
    }

    // For prenatal records, ensure prenatal keywords are included
    // even if not explicitly in the text
    if (healthData != null) {
      final prenatalFields = [
        'gravida',
        'para',
        'lmp',
        'edd',
        'gestationalAge',
        'aog',
        'fh',
      ];
      bool hasPrenatalFields = prenatalFields.any(
        (f) => healthData[f] != null && healthData[f].toString().isNotEmpty,
      );
      if (hasPrenatalFields) {
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
  });

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
    'timestamp': DateTime.now().toIso8601String(),
  };

  @override
  String toString() {
    return 'ClassificationResult(category: $category, severity: $severity, '
        'confidence: ${(confidence * 100).toStringAsFixed(1)}%, method: $method)';
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
