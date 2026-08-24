import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/utils/ocr_fuzzy_matcher.dart';

void main() {
  group('OcrFuzzyMatcher Tests', () {
    test('Levenshtein distance computes correctly', () {
      expect(OcrFuzzyMatcher.levenshtein('kitten', 'sitting'), 3);
      expect(OcrFuzzyMatcher.levenshtein('Casisang', 'Casisang'), 0);
      expect(OcrFuzzyMatcher.levenshtein('Casi5ang', 'Casisang'), 1);
      expect(OcrFuzzyMatcher.levenshtein('', 'Aglayan'), 7);
    });

    test('Similarity ratio is bounded [0.0, 1.0]', () {
      expect(OcrFuzzyMatcher.similarity('Casisang', 'Casisang'), 1.0);
      expect(OcrFuzzyMatcher.similarity('Fever', 'Fever'), 1.0);
      expect(OcrFuzzyMatcher.similarity('Fevor', 'Fever'), greaterThan(0.7));
    });

    test('Snaps noisy OCR tokens to correct Malaybalay Barangays', () {
      expect(OcrFuzzyMatcher.snapBarangay('Casi5ang'), 'Casisang');
      expect(OcrFuzzyMatcher.snapBarangay('Sump0ng'), 'Sumpong');
      expect(OcrFuzzyMatcher.snapBarangay('Aglayan'), 'Aglayan');
      expect(OcrFuzzyMatcher.snapBarangay('Magsaysay'), 'Magsaysay');
      expect(OcrFuzzyMatcher.snapBarangay('Poblacion 01'), 'Barangay 01');
      expect(OcrFuzzyMatcher.snapBarangay('Pob 2'), 'Barangay 02');
      expect(OcrFuzzyMatcher.snapBarangay('Barangay 03'), 'Barangay 03');
      expect(OcrFuzzyMatcher.snapBarangay('St. Peter'), 'Saint Peter');
      expect(OcrFuzzyMatcher.snapBarangay('Sto. Nino'), 'Santo Niño');
    });

    test('Snaps noisy clinical symptoms to clean dictionary terms', () {
      expect(OcrFuzzyMatcher.snapClinicalTerm('Fevor'), 'Fever');
      expect(OcrFuzzyMatcher.snapClinicalTerm('Coughing'), 'Cough');
      expect(OcrFuzzyMatcher.snapClinicalTerm('Headake'), 'Headache');
      expect(OcrFuzzyMatcher.snapClinicalTerm('Hypertenxion'), 'Hypertension');
      expect(OcrFuzzyMatcher.snapClinicalTerm('Diarrhea'), 'Diarrhea');
    });

    test('Expands common clinical acronyms', () {
      expect(OcrFuzzyMatcher.snapClinicalTerm('URTI'), 'Upper Respiratory Tract Infection');
      expect(OcrFuzzyMatcher.snapClinicalTerm('AGE'), 'Acute Gastroenteritis');
      expect(OcrFuzzyMatcher.snapClinicalTerm('UTI'), 'Urinary Tract Infection');
      expect(OcrFuzzyMatcher.snapClinicalTerm('CAP'), 'Community-Acquired Pneumonia');
      expect(OcrFuzzyMatcher.snapClinicalTerm('PTB'), 'Pulmonary Tuberculosis');
      expect(OcrFuzzyMatcher.snapClinicalTerm('HTN'), 'Hypertension');
      expect(OcrFuzzyMatcher.snapClinicalTerm('DM'), 'Diabetes Mellitus');
      expect(OcrFuzzyMatcher.snapClinicalTerm('AMI'), 'Acute Myocardial Infarction');
    });

    test('Translates Filipino (Tagalog/Cebuano) clinical symptom phrases', () {
      expect(OcrFuzzyMatcher.snapClinicalTerm('lagnat'), 'Fever');
      expect(OcrFuzzyMatcher.snapClinicalTerm('sinat'), 'Mild Fever');
      expect(OcrFuzzyMatcher.snapClinicalTerm('sipon'), 'Common Cold');
      expect(OcrFuzzyMatcher.snapClinicalTerm('sakit ng ulo'), 'Headache');
      expect(OcrFuzzyMatcher.snapClinicalTerm('pananakit ng tiyan'), 'Abdominal Pain');
      expect(OcrFuzzyMatcher.snapClinicalTerm('hilo'), 'Dizziness');
      expect(OcrFuzzyMatcher.snapClinicalTerm('nagtatae'), 'Diarrhea');
      expect(OcrFuzzyMatcher.snapClinicalTerm('altapresyon'), 'Hypertension');
      expect(OcrFuzzyMatcher.snapClinicalTerm('hika'), 'Asthma');
      expect(OcrFuzzyMatcher.snapClinicalTerm('trangkaso'), 'Flu');
      expect(OcrFuzzyMatcher.snapClinicalTerm('hirap huminga'), 'Difficulty Breathing');
    });

    test('Preserves arbitrary terms cleanly if below confidence', () {
      expect(OcrFuzzyMatcher.snapBarangay('xyz unrelated 123', minConfidence: 0.8), 'Xyz Unrelated 123');
      expect(OcrFuzzyMatcher.snapClinicalTerm('unknown complex condition with many words', minConfidence: 0.9), 'unknown complex condition with many words');
    });
  });
}

