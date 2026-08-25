import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Referral PDF & Workflow Tests', () {
    test('generates valid REF-2026 blank template PDF bytes', () async {
      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.referral,
        isBlank: true,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates valid REF-2026 completed referral record PDF bytes', () async {
      final referralRecord = {
        'id': 'REF-2026-0099',
        'patientName': 'Dela Cruz, Juan Miguel',
        'patientId': 'PAT-2026-0105',
        'patientAge': '34',
        'patientSex': 'Male',
        'patientAddress': 'Purok 4, Sayre Highway',
        'barangay': 'Casisang',
        'referralDateTime': '2026-08-25 09:30',
        'referredTo': 'City Health Office / Internal Medicine',
        'referralCategorySummary': 'Emergency',
        'referralReason': 'Hospital Capability',
        'chiefComplaint': 'Severe retrosternal chest pain radiating to left arm',
        'medicalHistory': 'Essential Hypertension (5 yrs, non-compliant)',
        'completeVitalSigns': 'BP: 160/100 mmHg | HR: 112 bpm | RR: 24 cpm | Temp: 37.0 C | SpO2: 94%',
        'impression': 'Hypertensive Urgency, rule out Acute Coronary Syndrome',
        'actionTaken': 'Administered sublingual ISDN, high-flow O2 at 4 LPM, dispatched emergency ambulance',
        'lastMealTime': '07:30 AM',
        'hasSurgicalOperations': false,
        'hasHealthInsuranceCoverage': true,
        'healthInsuranceCoverageType': 'PhilHealth Member',
        'assignedDoctorName': 'Dr. Ramon Reyes, MD',
        'createdByName': 'BHW Elena Bautista',
      };

      final bytes = await ClinicalFormPdfService.generateFormPdfBytes(
        formType: ClinicalFormType.referral,
        record: referralRecord,
        isBlank: false,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(1000));

      final outputDir = Directory('test_forms');
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }
      await File('${outputDir.path}/REF_2026_referral_filled.pdf').writeAsBytes(bytes);
    });

    test('getFormCode and getFormTitle return correct values for referral', () {
      expect(ClinicalFormPdfService.getFormCode(ClinicalFormType.referral), 'REF-2026');
      expect(ClinicalFormPdfService.getFormTitle(ClinicalFormType.referral), 'Standard Patient Referral Form');
    });
  });
}
