import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/disease_prediction_api_service.dart';

void main() {
  group('DiseasePredictionApiService fallback classification tests', () {
    test('classifies communicable symptoms correctly', () {
      final fallback = DiseasePredictionApiService.localHealthCategoryFallback(
        'Patient reports persistent fever and cough for 3 days',
      );
      expect(fallback['healthCategory'], 'Communicable');
      expect(fallback['ai_suggested_health_category'], 'Communicable');
      expect(fallback['healthCategoryKeywords'], contains('fever'));
      expect(fallback['healthCategoryKeywords'], contains('cough'));

      final guidance = SymptomGuidanceResult.fromFallback(
        fallbackMap: fallback,
      );
      expect(guidance.suggestedHealthCategory, 'Communicable');
      expect(guidance.recognizedSymptoms, contains('fever'));
      expect(guidance.homeCare.isNotEmpty, true);
      expect(guidance.homeCare.first, contains('hydration'));
    });

    test('classifies non-communicable symptoms correctly', () {
      final fallback = DiseasePredictionApiService.localHealthCategoryFallback(
        'Patient with history of hypertension and chronic chest pain',
      );
      expect(fallback['healthCategory'], 'Non-Communicable');
      expect(fallback['ai_suggested_health_category'], 'Non-Communicable');

      final guidance = SymptomGuidanceResult.fromFallback(
        fallbackMap: fallback,
      );
      expect(guidance.suggestedHealthCategory, 'Non-Communicable');
      expect(guidance.homeCare.isNotEmpty, true);
    });

    test('classifies mixed symptoms when both present', () {
      final fallback = DiseasePredictionApiService.localHealthCategoryFallback(
        'Patient with hypertension and acute fever',
      );
      expect(fallback['healthCategory'], 'Mixed');

      final guidance = SymptomGuidanceResult.fromFallback(
        fallbackMap: fallback,
      );
      expect(guidance.suggestedHealthCategory, 'Mixed');
    });

    test('returns Needs Clinical Review when no known keywords match', () {
      final fallback = DiseasePredictionApiService.localHealthCategoryFallback(
        'Patient feeling mildly unwell',
      );
      expect(fallback['healthCategory'], 'Needs Clinical Review');

      final guidance = SymptomGuidanceResult.fromFallback(
        fallbackMap: fallback,
      );
      expect(guidance.suggestedHealthCategory, 'Needs Clinical Review');
    });
  });
}
