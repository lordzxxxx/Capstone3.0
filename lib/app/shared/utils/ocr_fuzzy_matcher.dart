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
    // Also include named aliases
    final aliases = <String>[
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
    'Urinary Tract Infection',
    'Dengue Fever',
    'Tuberculosis',
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
    'Pneumonia',
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

    // Normalize Poblacion 1-11 patterns directly to canonical Barangay 01-11
    final pobsMatch = RegExp(r'^(?:poblacion|pob\.?)\s*0?(\d{1,2})$', caseSensitive: false).firstMatch(cleaned);
    if (pobsMatch != null) {
      final num = int.tryParse(pobsMatch.group(1)!);
      if (num != null && num >= 1 && num <= 11) {
        return 'Barangay ${num.toString().padLeft(2, '0')}';
      }
    }

    String bestMatch = cleaned;
    double highestScore = 0.0;

    for (final brgy in canonicalBarangays) {
      double score = similarity(cleaned, brgy);
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

    // For multi-item phrases, sentences, or phrases with conjunctions, preserve original text
    if (cleaned.contains(',') ||
        cleaned.contains(';') ||
        RegExp(r'\b(and|or|with|due\s+to|secondary\s+to)\b', caseSensitive: false).hasMatch(cleaned) ||
        cleaned.split(RegExp(r'\s+')).length > 2) {
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
