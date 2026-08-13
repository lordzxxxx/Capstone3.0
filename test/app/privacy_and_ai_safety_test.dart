import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/shared/privacy_notice.dart';

void main() {
  group('contextual mobile permission policy', () {
    test('explains camera access only for the selected OCR task', () {
      final text = OcrPermissionPolicy.rationale(
        ImageSource.camera,
        'Check-up',
      );

      expect(text, contains('only'));
      expect(text, contains('Check-up'));
      expect(text, contains('background'));
    });

    test('denial keeps unrelated/manual workflows available', () {
      final text = OcrPermissionPolicy.deniedMessage(
        ImageSource.gallery,
        code: 'photo_access_denied',
      );

      expect(text, contains('device Settings'));
      expect(text, contains('manual entry'));
    });

    test('non-permission picker errors remain a normal OCR error', () {
      final text = OcrPermissionPolicy.deniedMessage(
        ImageSource.camera,
        code: 'file_not_found',
      );

      expect(text, 'OCR could not read this image. Please try again.');
    });
  });

  test('privacy notice documents least-privilege location behavior', () {
    final notice = PrivacyNoticeContent.dialogText;
    expect(notice, contains('Location access is not currently requested'));
    expect(notice, contains('AI output is'));
    expect(notice, contains('device Settings app'));
  });

  group('AI decision support explainability', () {
    test(
      'exposes factors, uncertainty, escalation, and human review state',
      () async {
        final result = await HealthAIClassifier.instance.classify({
          'symptoms': 'crushing chest pain and difficulty breathing',
          'details': 'BP: 170/105',
          'age': '58',
          'vitalsigns': 'BP: 170/105',
        });

        final support = result.decisionSupport;
        expect(support, isNotNull);
        expect(support!.explanation, contains('decision support'));
        expect(support.influencingInformation, isNotEmpty);
        expect(support.riskFactors, isNotEmpty);
        expect(support.nextAction, contains('urgent'));
        expect(support.requiresHumanReview, isTrue);
        expect(support.reviewStatus, 'Pending human review');
        expect(result.recoveryPlan?['decision_support'], isA<Map>());
      },
    );

    test(
      'missing input is visible instead of being presented as certainty',
      () async {
        final result = await HealthAIClassifier.instance.classify({
          'symptoms': '',
          'details': '',
        });

        final support = result.decisionSupport!;
        expect(support.missingInformation, isNotEmpty);
        expect(support.requiresHumanReview, isTrue);
        expect(support.nextAction, contains('review'));
      },
    );
  });
}
