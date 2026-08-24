import 'dart:math';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';

/// Levenshtein distance and dictionary-matching fuzzy normalizer for AI-DSUHIS OCR.
class OcrFuzzyMatcher {
  OcrFuzzyMatcher._();

  /// Canonical list of Malaybalay City Barangays.
  static final List<String> canonicalBarangays = () {
    final list = <String>[];
    for (final b in MalaybalayBarangays.all) {
      if (!list.contains(b.name)) {
        list.add(b.name);
      }
    }
    // Also include named aliases and numeric variations
    final aliases = <String>[
      'Barangay 01', 'Barangay 02', 'Barangay 03', 'Barangay 04',
      'Barangay 05', 'Barangay 06', 'Barangay 07', 'Barangay 08',
      'Barangay 09', 'Barangay 10', 'Barangay 11',
      'Sumpong', 'Casisang', 'Magsaysay', 'Aglayan', 'Bangcud',
      'Can-ayan', 'Kalasungay', 'Dalwangan', 'Linabo', 'Managok',
      'San Jose', 'Laguitas', 'Kibalabag', 'Kulaman', 'Busdi',
      'Cabangahan', 'Caburacanan', 'Capitan Angel', 'Imbatug',
      'Indalasa', 'Mapayag', 'Mapulo', 'Miglamin', 'Patpat',
      'Saint Peter', 'San Martin', 'Santo Niño', 'Silae',
      'Simaya', 'Sinanglanan', 'Violeta', 'Zamboanguita',
    ];
    for (final a in aliases) {
      if (!list.contains(a)) {
        list.add(a);
      }
    }
    return list;
  }();

  /// Common clinical acronyms used in handwritten health records.
  static const Map<String, String> clinicalAcronyms = <String, String>{
    'URTI': 'Upper Respiratory Tract Infection',
    'AURI': 'Acute Upper Respiratory Infection',
    'URI': 'Upper Respiratory Infection',
    'AGE': 'Acute Gastroenteritis',
    'GE': 'Gastroenteritis',
    'UTI': 'Urinary Tract Infection',
    'CAP': 'Community-Acquired Pneumonia',
    'PNEUMONIA': 'Pneumonia',
    'PTB': 'Pulmonary Tuberculosis',
    'TB': 'Tuberculosis',
    'HTN': 'Hypertension',
    'HBP': 'High Blood Pressure',
    'DM': 'Diabetes Mellitus',
    'DM2': 'Type 2 Diabetes Mellitus',
    'T2DM': 'Type 2 Diabetes Mellitus',
    'T1DM': 'Type 1 Diabetes Mellitus',
    'MI': 'Myocardial Infarction',
    'AMI': 'Acute Myocardial Infarction',
    'DHF': 'Dengue Hemorrhagic Fever',
    'DF': 'Dengue Fever',
    'BA': 'Bronchial Asthma',
    'ASTHMA': 'Asthma',
    'PNC': 'Prenatal Checkup',
    'EPI': 'Immunization',
    'COPD': 'Chronic Obstructive Pulmonary Disease',
    'CVA': 'Cerebrovascular Accident (Stroke)',
  };

  /// Common Filipino (Tagalog/Cebuano) clinical symptom expressions mapped to canonical terms.
  static const Map<String, String> localSymptomMap = <String, String>{
    'lagnat': 'Fever',
    'sinat': 'Mild Fever',
    'mataas na lagnat': 'High Fever',
    'ubo': 'Cough',
    'sipon': 'Common Cold',
    'sakit ng ulo': 'Headache',
    'pananakit ng ulo': 'Headache',
    'sakit ng tiyan': 'Abdominal Pain',
    'pananakit ng tiyan': 'Abdominal Pain',
    'hilo': 'Dizziness',
    'pagkahilo': 'Dizziness',
    'nagtatae': 'Diarrhea',
    'pagtatae': 'Diarrhea',
    'sumusuka': 'Vomiting',
    'pagsusuka': 'Vomiting',
    'altapresyon': 'Hypertension',
    'mataas ang presyon': 'High Blood Pressure',
    'hika': 'Asthma',
    'trangkaso': 'Flu',
    'panghihina': 'Body Weakness',
    'panghihina ng katawan': 'Body Weakness',
    'walang gana': 'Loss of Appetite',
    'kawalan ng gana': 'Loss of Appetite',
    'pananakit ng dibdib': 'Chest Pain',
    'hirap huminga': 'Difficulty Breathing',
    'pantal': 'Skin Rash',
    'singaw': 'Mouth Sores',
    'rashes': 'Skin Rash',
    'masakit ang lalamunan': 'Sore Throat',
  };

  /// Standard Clinical Symptoms & Diagnoses Dictionary.
  static const List<String> clinicalDictionary = <String>[
    'Fever',
    'Cough',
    'Headache',
    'Hypertension',
    'Diabetes Mellitus',
    'Asthma',
    'Diarrhea',
    'Vomiting',
    'Abdominal Pain',
    'Fatigue',
    'Difficulty Breathing',
    'Shortness of Breath',
    'Chest Pain',
    'Skin Rash',
    'Dizziness',
    'Prenatal Checkup',
    'Immunization',
    'Upper Respiratory Tract Infection',
    'Acute Upper Respiratory Infection',
    'Urinary Tract Infection',
    'Dengue Fever',
    'Dengue Hemorrhagic Fever',
    'Tuberculosis',
    'Pulmonary Tuberculosis',
    'Malnutrition',
    'Loss of Appetite',
    'Nausea',
    'Body Weakness',
    'Sore Throat',
    'High Blood Pressure',
    'High Fever',
    'Flu',
    'Common Cold',
    'Gastroenteritis',
    'Acute Gastroenteritis',
    'Pneumonia',
    'Community-Acquired Pneumonia',
    'Acute Myocardial Infarction',
    'Bronchial Asthma',
  ];

  /// Standard Levenshtein Distance implementation in pure Dart.
  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final sRunes = s.toLowerCase().trim().runes.toList();
    final tRunes = t.toLowerCase().trim().runes.toList();

    List<int> v0 = List<int>.generate(tRunes.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(tRunes.length + 1, 0);

    for (int i = 0; i < sRunes.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < tRunes.length; j++) {
        int cost = (sRunes[i] == tRunes[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= tRunes.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[tRunes.length];
  }

  /// Calculates normalized string similarity ratio [0.0 to 1.0].
  static double similarity(String s, String t) {
    final sClean = s.toLowerCase().trim();
    final tClean = t.toLowerCase().trim();
    if (sClean == tClean) return 1.0;
    if (sClean.isEmpty || tClean.isEmpty) return 0.0;

    // Stem / Prefix match bonus
    if (sClean.startsWith(tClean) || tClean.startsWith(sClean)) {
      int minLen = min(sClean.length, tClean.length);
      int maxLen = max(sClean.length, tClean.length);
      return max(0.85, minLen / maxLen);
    }

    int maxLen = max(sClean.length, tClean.length);
    if (maxLen == 0) return 1.0;
    int dist = levenshtein(sClean, tClean);
    return max(0.0, 1.0 - (dist / maxLen));
  }

  /// Snaps raw OCR string to closest Malaybalay Barangay if similarity >= threshold (default 60%).
  static String snapBarangay(String rawInput, {double minConfidence = 0.60}) {
    final cleaned = rawInput.trim();
    if (cleaned.isEmpty) return '';

    // Handle common abbreviations like "St. Peter" -> "Saint Peter", "Sto. Nino" -> "Santo Niño"
    final normalizedAlias = cleaned
        .replaceAll(RegExp(r'\bst\.?\s*peter\b', caseSensitive: false), 'Saint Peter')
        .replaceAll(RegExp(r'\bsto\.?\s*ni[nñ]o\b', caseSensitive: false), 'Santo Niño')
        .replaceAll(RegExp(r'\bsta\.?\s*', caseSensitive: false), 'Santa ');

    // Normalize Poblacion / Barangay 1-11 patterns directly to canonical Barangay 01-11
    final pobsMatch = RegExp(
      r'^(?:poblacion|pob\.?|barangay|brgy\.?|bgy\.?)\s*0?(\d{1,2})$',
      caseSensitive: false,
    ).firstMatch(normalizedAlias);
    if (pobsMatch != null) {
      final num = int.tryParse(pobsMatch.group(1)!);
      if (num != null && num >= 1 && num <= 11) {
        return 'Barangay ${num.toString().padLeft(2, '0')}';
      }
    }

    // Bare number 1-11 when inside barangay field
    final bareNum = int.tryParse(normalizedAlias);
    if (bareNum != null && bareNum >= 1 && bareNum <= 11) {
      return 'Barangay ${bareNum.toString().padLeft(2, '0')}';
    }

    String bestMatch = cleaned;
    double highestScore = 0.0;

    for (final brgy in canonicalBarangays) {
      double score = similarity(normalizedAlias, brgy);
      if (score > highestScore) {
        highestScore = score;
        bestMatch = brgy;
      }
    }

    if (highestScore >= minConfidence) {
      return bestMatch;
    }
    return toTitleCase(cleaned);
  }

  /// Snaps raw OCR string to clinical symptoms & conditions.
  static String snapClinicalTerm(String rawInput, {double minConfidence = 0.70}) {
    final cleaned = rawInput.trim();
    if (cleaned.isEmpty) return '';

    // Check direct acronym expansions
    final upperKey = cleaned.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clinicalAcronyms.containsKey(upperKey)) {
      return clinicalAcronyms[upperKey]!;
    }

    // Check local Filipino translations
    final lowerKey = cleaned.toLowerCase().trim();
    if (localSymptomMap.containsKey(lowerKey)) {
      return localSymptomMap[lowerKey]!;
    }

    // For multi-item phrases, sentences, or phrases with conjunctions, preserve original text
    if (cleaned.contains(',') ||
        cleaned.contains(';') ||
        RegExp(r'\b(and|or|with|due\s+to|secondary\s+to)\b', caseSensitive: false).hasMatch(cleaned) ||
        cleaned.split(RegExp(r'\s+')).length > 3) {
      return cleaned;
    }

    String bestMatch = cleaned;
    double highestScore = 0.0;

    for (final term in clinicalDictionary) {
      double score = similarity(cleaned, term);
      if (score > highestScore) {
        highestScore = score;
        bestMatch = term;
      }
    }

    if (highestScore >= minConfidence) {
      return bestMatch;
    }
    return cleaned;
  }

  /// Converts arbitrary text to Title Case.
  static String toTitleCase(String text) {
    if (text.isEmpty) return '';
    return text.split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
