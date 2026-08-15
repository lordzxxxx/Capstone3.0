import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mycapstone_project/app/core/services/disease_prediction_api_service.dart';

void main() {
  test('parseSymptoms separates, trims, and de-duplicates staff input', () {
    expect(
      DiseasePredictionApiService.parseSymptoms(
        ' fever, headache; cough\nFEVER ',
      ),
      ['fever', 'headache', 'cough'],
    );
  });

  test(
    'legacy disease prediction is disabled without a network call',
    () async {
      final service = DiseasePredictionApiService(
        client: MockClient((_) => throw StateError('must not be called')),
        baseUrl: 'http://api.test',
      );
      expect(
        () => service.predictFromText('fever'),
        throwsA(
          isA<DiseasePredictionApiException>().having(
            (error) => error.message,
            'message',
            contains('disabled'),
          ),
        ),
      );
      service.close();
    },
  );

  test(
    'symptom guidance sends security tokens and maps care without diagnosis',
    () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'http://api.test/guidance');
        expect(request.headers['authorization'], 'Bearer user-token');
        expect(request.headers['x-firebase-appcheck'], 'app-check-token');
        expect(jsonDecode(request.body), {
          'symptoms': ['fever', 'cough'],
        });
        return http.Response(
          jsonEncode({
            'recognizedSymptoms': ['fever', 'cough'],
            'recognizedConditions': <String>[],
            'ignoredSymptoms': <String>[],
            'matchedGuidanceSymptoms': ['fever', 'cough'],
            'missingGuidanceSymptoms': <String>[],
            'matchedGuidanceConditions': <String>[],
            'missingGuidanceConditions': <String>[],
            'homeCare': ['Rest and drink fluids.'],
            'precautions': ['Do not use leftover antibiotics.'],
            'whenToSeekCare': ['Contact a clinician if symptoms worsen.'],
            'emergencyWarningSigns': ['Difficulty breathing.'],
            'references': <Map<String, dynamic>>[],
            'contentAvailable': true,
            'disclaimer': 'Educational guidance only.',
          }),
          200,
        );
      });
      final service = SymptomGuidanceApiService(
        client: client,
        baseUrl: 'http://api.test',
        securityHeadersProvider: () async => {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer user-token',
          'X-Firebase-AppCheck': 'app-check-token',
        },
      );

      final result = await service.getGuidanceFromText('fever, cough');

      expect(result.recognizedSymptoms, ['fever', 'cough']);
      expect(result.homeCare, ['Rest and drink fluids.']);
      expect(result.emergencyWarningSigns, ['Difficulty breathing.']);
      expect(result.toRecordFields().containsKey('ai_confidence'), isFalse);
      final recordFields = result.toRecordFields();
      final recoveryPlan = recordFields['ai_recovery_plan'] as Map;
      expect(recoveryPlan['decision_support'], isA<Map>());
      expect(
        (recoveryPlan['decision_support'] as Map)['requires_human_review'],
        isTrue,
      );
      service.close();
    },
  );

  test(
    'unconfigured guidance reports a safe unavailable state without a network call',
    () async {
      final service = SymptomGuidanceApiService(
        client: MockClient((_) => throw StateError('must not be called')),
        baseUrl: '',
        securityHeadersProvider: () async => const {},
      );

      await expectLater(
        service.getGuidanceFromText('fever'),
        throwsA(
          isA<SymptomGuidanceApiException>().having(
            (error) => error.message,
            'message',
            allOf(contains('not configured'), contains('still be saved')),
          ),
        ),
      );
      service.close();
    },
  );
}
