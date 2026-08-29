import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';

void main() {
  group('HealthScreeningEngine', () {
    test('returns a non-diagnostic within-range result for valid readings', () {
      final result = HealthScreeningEngine.evaluate({
        'age': '30',
        'vitalsigns':
            'BP: 118/76 mmHg, Temp: 36.8°C, HR: 72 bpm, RR: 16 brpm, O2: 98%',
      });

      expect(result.status, HealthScreeningStatus.withinExpectedRange);
      expect(result.dataQuality, HealthDataQuality.complete);
      expect(
        result.referralRecommendation,
        HealthReferralRecommendation.noCurrentReferralIndication,
      );
      expect(
        result.warnings.single,
        'No screening warning identified from the currently recorded measurements.',
      );
      expect(result.findings, hasLength(5));
    });

    test('keeps malformed measurements as data-quality issues', () {
      final result = HealthScreeningEngine.evaluate({
        'age': '30',
        'vitalsigns': 'BP: not-a-reading, Temp: -4°C, HR: -10 bpm',
      });

      expect(result.dataQuality, HealthDataQuality.needsVerification);
      expect(result.status, HealthScreeningStatus.needsProfessionalReview);
      expect(result.qualityIssues, hasLength(3));
      expect(
        result.findings.where((finding) => !finding.isInformational),
        isEmpty,
      );
      expect(
        result.referralRecommendation,
        HealthReferralRecommendation.continueMonitoring,
      );
    });

    test('does not apply adult heart-rate thresholds to children', () {
      final result = HealthScreeningEngine.evaluate({
        'age': 3,
        'heartRate': 145,
      });

      expect(result.status, HealthScreeningStatus.needsProfessionalReview);
      expect(
        result.findings.single.status,
        HealthScreeningStatus.needsProfessionalReview,
      );
      expect(
        result.findings.single.reason,
        contains('does not apply an adult heart-rate threshold'),
      );
    });

    test('uses age-specific respiratory-rate context for children', () {
      final result = HealthScreeningEngine.evaluate({
        'age': 3,
        'respiratoryRate': 45,
      });

      expect(result.status, HealthScreeningStatus.referralReview);
      expect(result.findings.single.measurement, 'Respiratory rate');
      expect(result.findings.single.reason, contains('age-specific WHO'));
    });

    test(
      'classifies elevated blood pressure as attention before severe escalation',
      () {
        final result = HealthScreeningEngine.evaluate({
          'age': 45,
          'bloodPressure': '170/108',
        });

        expect(result.status, HealthScreeningStatus.needsAttention);
        expect(
          result.referralRecommendation,
          HealthReferralRecommendation.considerReferral,
        );
        expect(result.findings.single.recordedValue, '170/108 mmHg');
      },
    );

    test(
      'recommends referral for severe blood pressure without diagnosing',
      () {
        final result = HealthScreeningEngine.evaluate({
          'age': 45,
          'bloodPressure': '195/125',
        });

        expect(result.status, HealthScreeningStatus.referralReview);
        expect(
          result.referralRecommendation,
          HealthReferralRecommendation.referralRecommended,
        );
        expect(result.suggestedAction, contains('existing referral workflow'));
      },
    );

    test(
      'escalates severe blood pressure with concerning symptoms urgently',
      () {
        final result = HealthScreeningEngine.evaluate({
          'age': 45,
          'bloodPressure': '195/125',
          'symptoms': 'chest pain',
        });

        expect(result.status, HealthScreeningStatus.urgentAssessment);
        expect(
          result.referralRecommendation,
          HealthReferralRecommendation.urgentProfessionalAssessment,
        );
        expect(
          result.findings.map((finding) => finding.status),
          contains(HealthScreeningStatus.urgentAssessment),
        );
      },
    );

    test('combines oxygen and respiratory findings for referral review', () {
      final result = HealthScreeningEngine.evaluate({
        'age': 30,
        'oxygenSaturation': 90,
        'respiratoryRate': 34,
      });

      expect(result.status, HealthScreeningStatus.referralReview);
      expect(result.referralReasons, hasLength(2));
      expect(
        result.referralRecommendation,
        HealthReferralRecommendation.referralRecommended,
      );
    });

    test('uses urgent pregnancy warning logic when context is explicit', () {
      final result = HealthScreeningEngine.evaluate({
        'age': 28,
        'pregnant': true,
        'bloodPressure': '165/112',
        'symptoms': 'severe headache and blurred vision',
      });

      expect(result.status, HealthScreeningStatus.urgentAssessment);
      expect(
        result.referralRecommendation,
        HealthReferralRecommendation.urgentProfessionalAssessment,
      );
      expect(
        result.findings.map((finding) => finding.measurement),
        contains('Pregnancy warning signs'),
      );
    });

    test(
      'preserves the structured result in the existing recovery-plan field',
      () {
        final result = HealthScreeningEngine.evaluate({
          'age': 30,
          'temperature': 36.7,
        });
        final attached = HealthScreeningEngine.attachToRecord({
          'id': 'checkup-1',
          'ai_recovery_plan': {'general_advice': <String>[]},
        }, result);

        final restored = HealthScreeningEngine.resultFromRecord(attached);
        expect(restored, isNotNull);
        expect(restored!.status, result.status);
        expect(restored.ruleVersion, HealthScreeningEngine.ruleVersion);
        expect(attached['ai_screening_status'], result.status.label);
        expect(
          (attached['ai_recovery_plan'] as Map)['general_advice'],
          isNotNull,
        );
      },
    );

    test('aggregates only persisted screening results', () {
      final within = HealthScreeningEngine.attachToRecord({
        'id': 'within',
      }, HealthScreeningEngine.evaluate({'age': 30, 'temperature': 36.7}));
      final urgent = HealthScreeningEngine.attachToRecord(
        {'id': 'urgent'},
        HealthScreeningEngine.evaluate({
          'age': 30,
          'oxygenSaturation': 90,
          'symptoms': 'difficulty breathing',
        }),
      );

      final summary = HealthScreeningInsightSummary.fromRecords([
        within,
        urgent,
        {'id': 'legacy-without-screening', 'vitalsigns': 'BP: 190/120'},
      ]);

      expect(summary.evaluatedScreenings, 2);
      expect(summary.withinExpectedRange, 1);
      expect(summary.urgentFindings, 1);
      expect(summary.referralRecommendations, 1);
      expect(summary.flaggedMeasurements['Oxygen saturation'], 1);
    });
  });
}
